
#!/usr/bin/env python3
"""
malgus_cloudfront_log_explainer.py

Counts CloudFront cache outcomes (Hit / Miss / RefreshHit) from CloudFront *standard logs*
stored in S3 (tab-delimited, often .gz).

# Reason why Darth Malgus would be pleased with this script:
# The Empire doesn’t argue with feelings. It counts outcomes. Hit. Miss. RefreshHit. Evidence only.
#
# Reason why this script is relevant to your career:
# Cache behavior = latency + cost + origin stability. Being able to prove Hit/Miss rates is platform engineering reality.
#
# How you would talk about this script at an interview:
# “I wrote a small S3-backed log analyzer that downloads recent CloudFront standard logs,
#  parses x-edge-result-type, and reports Hit/Miss/RefreshHit metrics to validate caching policy.”
"""

import argparse
import gzip
import io
import os
import subprocess
import sys
import tempfile
from collections import Counter
from typing import Dict, List, Optional

TARGETS = {"Hit", "Miss", "RefreshHit"}

def run(cmd: List[str]) -> str:
    """Run a command and return stdout; raise with clear error if it fails."""
    try:
        p = subprocess.run(cmd, check=True, capture_output=True, text=True)
        return p.stdout
    except FileNotFoundError:
        raise RuntimeError("Command not found. Install AWS CLI v2 and ensure 'aws' is on PATH.")
    except subprocess.CalledProcessError as e:
        msg = e.stderr.strip() or e.stdout.strip() or str(e)
        raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{msg}")

def aws_s3_ls_recursive(bucket: str, prefix: str) -> List[str]:
    """
    Return object keys from `aws s3 ls s3://bucket/prefix --recursive`.
    """
    uri = f"s3://{bucket}/{prefix}" if prefix else f"s3://{bucket}/"
    out = run(["aws", "s3", "ls", uri, "--recursive"])
    keys = []
    for line in out.splitlines():
        # format: 2025-12-29 12:34:56   12345 some/prefix/file.gz
        parts = line.split()
        if len(parts) >= 4:
            key = parts[3]
            # skip "folders" if any
            if key.endswith("/"):
                continue
            keys.append(key)
    return keys

def pick_latest(keys: List[str], n: int) -> List[str]:
    """
    AWS 's3 ls' is already sorted lexicographically by key within listing order,
    but not guaranteed by timestamp across prefixes. We can just take the last N
    if your logs are date-partitioned (common). This is good enough for labs.
    """
    if n <= 0:
        return []
    return keys[-n:] if len(keys) > n else keys

def aws_s3_cp(bucket: str, key: str, dest_path: str) -> None:
    run(["aws", "s3", "cp", f"s3://{bucket}/{key}", dest_path])

def open_maybe_gzip(path: str) -> io.TextIOBase:
    if path.endswith(".gz"):
        return io.TextIOWrapper(gzip.open(path, "rb"), encoding="utf-8", errors="replace")
    return open(path, "r", encoding="utf-8", errors="replace")

def count_standard_log_files(file_paths: List[str]) -> Dict[str, int]:
    """
    Parse CloudFront standard logs. Uses '#Fields:' header to map columns.
    Counts x-edge-result-type primarily, falls back to x-edge-response-result-type.
    """
    counts = Counter()
    other = Counter()

    for path in file_paths:
        field_index: Optional[Dict[str, int]] = None

        with open_maybe_gzip(path) as f:
            for line in f:
                if line.startswith("#Fields:"):
                    # Example: "#Fields: date time x-edge-location ... x-edge-result-type x-edge-response-result-type ..."
                    _, fields_str = line.split(":", 1)
                    fields = fields_str.strip().split()
                    field_index = {name: idx for idx, name in enumerate(fields)}
                    continue

                if not line or line.startswith("#"):
                    continue

                if not field_index:
                    # If no header was found, skip safely (standard logs almost always include it).
                    other["(missing_fields_header)"] += 1
                    continue

                parts = line.rstrip("\n").split("\t")

                def get_field(name: str) -> str:
                    idx = field_index.get(name)
                    if idx is None:
                        return ""
                    if idx >= len(parts):
                        return ""
                    return parts[idx]

                rt = get_field("x-edge-result-type")
                rrt = get_field("x-edge-response-result-type")
                outcome = rt or rrt

                if not outcome:
                    other["(missing_outcome)"] += 1
                elif outcome in TARGETS:
                    counts[outcome] += 1
                else:
                    other[outcome] += 1

    # roll up other outcomes
    for k, v in other.items():
        counts[f"Other:{k}"] += v

    return dict(counts)

def print_report(counts: Dict[str, int]) -> None:
    core = {k: counts.get(k, 0) for k in ["Hit", "Miss", "RefreshHit"]}
    others = {k: v for k, v in counts.items() if k not in core}

    total_core = sum(core.values())
    total_all = sum(counts.values())

    def pct(n: int, d: int) -> str:
        return "0.0%" if d == 0 else f"{(n * 100.0 / d):.1f}%"

    print("\n=== CloudFront Cache Outcome Report (Standard Logs) ===")
    print(f"Core total (Hit/Miss/RefreshHit): {total_core}")
    print(f"All counted lines/notes:          {total_all}\n")

    print("Core outcomes:")
    for k in ["Hit", "Miss", "RefreshHit"]:
        v = core[k]
        print(f"  {k:10s} {v:8d}   ({pct(v, total_core)} of core)")

    if others:
        print("\nOther outcomes / parsing notes (top 20):")
        for k, v in sorted(others.items(), key=lambda x: (-x[1], x[0]))[:20]:
            print(f"  {k:28s} {v:8d}")

    print("\nInterpretation (ops):")
    print("  • High Hit% usually means lower latency & lower origin load.")
    print("  • High Miss% suggests caching policy mismatch, uncacheable headers,")
    print("    query-string/cookie variance, or origin Cache-Control behavior.")
    print("  • RefreshHit means CloudFront revalidated with origin and served cached content (often good).")
    print("=======================================================\n")

def main() -> int:
    ap = argparse.ArgumentParser(description="Count Hit/Miss/RefreshHit from CloudFront standard logs in S3.")
    ap.add_argument("--bucket", default="Class_Lab3", help="S3 bucket name (default: Class_Lab3)")
    ap.add_argument("--prefix", default="", help="Optional S3 prefix (folder) where logs live, e.g. cloudfront-logs/")
    ap.add_argument("--latest", type=int, default=3, help="Download and analyze the latest N log objects (default: 3)")
    ap.add_argument("--keep", action="store_true", help="Keep downloaded files (default: delete temp files)")
    args = ap.parse_args()

    # 1) List objects
    keys = aws_s3_ls_recursive(args.bucket, args.prefix)
    if not keys:
        print(f"No objects found in s3://{args.bucket}/{args.prefix}")
        print("Tip: verify prefix with: aws s3 ls s3://Class_Lab3/ --recursive | head")
        return 2

    latest_keys = pick_latest(keys, args.latest)
    print(f"Found {len(keys)} objects. Analyzing latest {len(latest_keys)}:")
    for k in latest_keys:
        print(f"  - s3://{args.bucket}/{k}")

    # 2) Download into temp dir
    tmpdir = tempfile.mkdtemp(prefix="malgus_cf_")
    downloaded = []
    try:
        for k in latest_keys:
            filename = os.path.basename(k) or "log"
            dest = os.path.join(tmpdir, filename)
            aws_s3_cp(args.bucket, k, dest)
            downloaded.append(dest)

        # 3) Parse + report
        counts = count_standard_log_files(downloaded)
        print_report(counts)

        if args.keep:
            print(f"Kept downloaded files in: {tmpdir}")
        else:
            # cleanup
            for p in downloaded:
                try:
                    os.remove(p)
                except OSError:
                    pass
            try:
                os.rmdir(tmpdir)
            except OSError:
                pass

        return 0
    except RuntimeError as e:
        print(str(e), file=sys.stderr)
        print("\nQuick checks:")
        print("  aws sts get-caller-identity")
        print(f"  aws s3 ls s3://{args.bucket}/{args.prefix} --recursive | tail -n 20")
        return 1

if __name__ == "__main__":
    raise SystemExit(main())