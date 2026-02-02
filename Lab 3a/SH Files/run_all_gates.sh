#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# run_all_gates.sh — SEIR Lab 2 Gate (CloudFront + WAF + Route53 + TLS + Logging + Origin protection)
#
# Outputs:
#   - gate_result.json (default)
#   - badge.txt        (GREEN|YELLOW|RED)
#   - pr_comment.md    (human feedback)
#
# Exit codes:
#   0 = PASS
#   2 = FAIL
#   1 = ERROR (missing prereqs)
#
# Notes:
# - CloudFront requires ACM certs in us-east-1.
# - Route53 alias HostedZoneId for CloudFront is constant: Z2FDTNDATAQYW2
# - Origin "VPC only reachable via CloudFront" is enforced indirectly via:
#     * Origin SG must not allow 0.0.0.0/0 on app ports
#     * Prefer CloudFront origin-facing prefix list (recommended) or tightly scoped CIDRs
# ============================================================

# ---------- Required inputs (env vars) ----------
# Region of your *origin resources* (EC2/ALB/etc.)
ORIGIN_REGION="${ORIGIN_REGION:-us-east-1}"

# CloudFront Distribution ID (e.g. E1ABCDEF234567)
CF_DISTRIBUTION_ID="${CF_DISTRIBUTION_ID:-}"

# Domain you are serving (e.g. chewbacca-growls.com)
DOMAIN_NAME="${DOMAIN_NAME:-}"

# Route53 Hosted Zone ID for your domain (e.g. Z123ABC...)
ROUTE53_ZONE_ID="${ROUTE53_ZONE_ID:-}"

# Optional but strongly recommended: ACM cert ARN used by CloudFront (in us-east-1)
ACM_CERT_ARN="${ACM_CERT_ARN:-}"

# Optional: expected WAFv2 Web ACL ARN (scope CLOUDFRONT). If omitted, we still verify association exists.
WAF_WEB_ACL_ARN="${WAF_WEB_ACL_ARN:-}"

# Optional: log bucket (S3) name where CloudFront standard logs are delivered
LOG_BUCKET="${LOG_BUCKET:-}"

# Optional: origin security group ID (ALB SG or EC2 SG that receives CloudFront traffic)
ORIGIN_SG_ID="${ORIGIN_SG_ID:-}"

# Optional: app ports to check on origin SG (comma-separated)
APP_PORTS="${APP_PORTS:-443,80}"

# Optional: warn/fail controls
REQUIRE_LOGGING="${REQUIRE_LOGGING:-true}"        # true/false
REQUIRE_WAF_ASSOCIATION="${REQUIRE_WAF_ASSOCIATION:-true}"  # true/false

# Output files
OUT_JSON="${OUT_JSON:-gate_result.json}"
BADGE_TXT="${BADGE_TXT:-badge.txt}"
PR_COMMENT_MD="${PR_COMMENT_MD:-pr_comment.md}"

# SLA persistence (optional but helpful)
SLA_HOURS="${SLA_HOURS:-24}"
STATE_DIR="${STATE_DIR:-.gate_state}"
STATE_FILE="${STATE_FILE:-.gate_state/lab2_first_seen_utc.txt}"

# ---------- Constants ----------
CF_ACM_REGION="us-east-1"
CF_ROUTE53_ALIAS_ZONE_ID="Z2FDTNDATAQYW2"

# ---------- Helpers ----------
now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }
mkdirp() { mkdir -p "$1" >/dev/null 2>&1 || true; }

json_escape() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'
}

iso_to_epoch() { date -u -d "$1" +%s 2>/dev/null || echo ""; }
epoch_to_iso() { date -u -d "@$1" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo ""; }

# Arrays for roll-up
details=()
warnings=()
failures=()

add_detail() { details+=("$1"); }
add_warning() { warnings+=("$1"); }
add_failure() { failures+=("$1"); }

usage() {
  cat <<EOF
Required env vars:
  CF_DISTRIBUTION_ID  CloudFront distribution ID (e.g. E1ABCDEF234567)
  DOMAIN_NAME         Domain name served by CloudFront (e.g. chewbacca-growls.com)
  ROUTE53_ZONE_ID     Hosted zone ID for the domain (e.g. Z123ABC...)

Recommended env vars:
  ACM_CERT_ARN        ACM cert ARN (in us-east-1) used by CloudFront
  WAF_WEB_ACL_ARN     WAFv2 Web ACL ARN (CLOUDFRONT scope)
  LOG_BUCKET          S3 bucket for CloudFront logs
  ORIGIN_SG_ID        Security group protecting the origin (ALB/EC2)
  ORIGIN_REGION       Region of origin resources (default: us-east-1)

Examples:
  ORIGIN_REGION=us-east-1 \\
  CF_DISTRIBUTION_ID=E1ABCDEF234567 \\
  DOMAIN_NAME=chewbacca-growls.com \\
  ROUTE53_ZONE_ID=Z123ABC456DEF \\
  ACM_CERT_ARN=arn:aws:acm:us-east-1:123456789012:certificate/.... \\
  WAF_WEB_ACL_ARN=arn:aws:wafv2:us-east-1:123456789012:global/webacl/... \\
  LOG_BUCKET=chewbacca-logs \\
  ORIGIN_SG_ID=sg-0123456789abcdef0 \\
  ./run_all_gates.sh
EOF
}

badge_from() {
  local status="$1"
  local warn_count="$2"
  if [[ "$status" == "FAIL" ]]; then echo "RED"; return; fi
  if [[ "$warn_count" -gt 0 ]]; then echo "YELLOW"; return; fi
  echo "GREEN"
}

need_env() {
  if [[ -z "$CF_DISTRIBUTION_ID" || -z "$DOMAIN_NAME" || -z "$ROUTE53_ZONE_ID" ]]; then
    echo "ERROR: CF_DISTRIBUTION_ID, DOMAIN_NAME, ROUTE53_ZONE_ID are required." >&2
    usage >&2
    exit 1
  fi
}

# ---------- Preconditions ----------
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi
if ! have_cmd aws; then
  echo "ERROR: aws CLI not found on PATH." >&2
  exit 1
fi

need_env

# ---------- Start ----------
ts_now="$(now_utc)"
caller_arn="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "")"
if [[ -n "$caller_arn" ]]; then
  add_detail "PASS: AWS credentials OK (caller=$caller_arn)."
else
  add_failure "FAIL: aws sts get-caller-identity failed (credentials/permissions)."
fi

# ---------- Fetch CloudFront distribution ----------
cf_json="$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" 2>/dev/null || true)"
if [[ -z "$cf_json" ]]; then
  add_failure "FAIL: CloudFront distribution not found or no permission (ID=$CF_DISTRIBUTION_ID)."
else
  add_detail "PASS: CloudFront distribution retrieved (ID=$CF_DISTRIBUTION_ID)."
fi

# Parse key fields (best-effort using --query to avoid jq dependency)
cf_enabled="$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" \
  --query "Distribution.DistributionConfig.Enabled" --output text 2>/dev/null || echo "Unknown")"
cf_status="$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" \
  --query "Distribution.Status" --output text 2>/dev/null || echo "Unknown")"
cf_domain="$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" \
  --query "Distribution.DomainName" --output text 2>/dev/null || echo "")"
cf_aliases="$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" \
  --query "Distribution.DistributionConfig.Aliases.Items" --output text 2>/dev/null || echo "")"

# Check: enabled + deployed
if [[ "$cf_enabled" == "True" ]]; then
  add_detail "PASS: CloudFront Enabled=True."
else
  add_failure "FAIL: CloudFront is not enabled (Enabled=$cf_enabled)."
fi

if [[ "$cf_status" == "Deployed" ]]; then
  add_detail "PASS: CloudFront Status=Deployed."
else
  add_warning "WARN: CloudFront Status is not Deployed yet (Status=$cf_status)."
fi

# Check: alias contains domain
if echo "$cf_aliases" | tr '\t' '\n' | grep -qi "^${DOMAIN_NAME}$"; then
  add_detail "PASS: CloudFront aliases include domain ($DOMAIN_NAME)."
else
  add_failure "FAIL: CloudFront aliases do NOT include domain ($DOMAIN_NAME)."
fi

# Check: ViewerCertificate / ACM
viewer_cert_source="$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" \
  --query "Distribution.DistributionConfig.ViewerCertificate.CertificateSource" --output text 2>/dev/null || echo "Unknown")"
viewer_acm_arn="$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" \
  --query "Distribution.DistributionConfig.ViewerCertificate.ACMCertificateArn" --output text 2>/dev/null || echo "")"
min_tls="$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" \
  --query "Distribution.DistributionConfig.ViewerCertificate.MinimumProtocolVersion" --output text 2>/dev/null || echo "")"

if [[ -n "$viewer_acm_arn" && "$viewer_acm_arn" != "None" ]]; then
  add_detail "PASS: CloudFront uses ACM certificate (ACM ARN present)."
  if [[ -n "$ACM_CERT_ARN" && "$viewer_acm_arn" != "$ACM_CERT_ARN" ]]; then
    add_warning "WARN: CloudFront ACM ARN differs from ACM_CERT_ARN input (expected=$ACM_CERT_ARN, actual=$viewer_acm_arn)."
  fi
else
  add_failure "FAIL: CloudFront does not appear to use an ACM cert (ACMCertificateArn missing)."
fi

# TLS min protocol sanity
if [[ -n "$min_tls" ]]; then
  if echo "$min_tls" | grep -q "TLSv1.2"; then
    add_detail "PASS: Minimum TLS includes TLSv1.2 (MinimumProtocolVersion=$min_tls)."
  else
    add_warning "WARN: Minimum TLS is not TLSv1.2+ (MinimumProtocolVersion=$min_tls)."
  fi
else
  add_warning "WARN: Could not determine MinimumProtocolVersion."
fi

# Validate ACM cert (CloudFront certs must be in us-east-1)
acm_to_check="${ACM_CERT_ARN:-$viewer_acm_arn}"
if [[ -n "$acm_to_check" ]]; then
  cert_status="$(aws acm describe-certificate --certificate-arn "$acm_to_check" --region "$CF_ACM_REGION" \
    --query "Certificate.Status" --output text 2>/dev/null || echo "Unknown")"
  cert_domains="$(aws acm describe-certificate --certificate-arn "$acm_to_check" --region "$CF_ACM_REGION" \
    --query "Certificate.SubjectAlternativeNames" --output text 2>/dev/null || echo "")"

  if [[ "$cert_status" == "ISSUED" ]]; then
    add_detail "PASS: ACM certificate is ISSUED (us-east-1)."
  else
    add_failure "FAIL: ACM certificate is not ISSUED (Status=$cert_status)."
  fi

  if echo "$cert_domains" | tr '\t' '\n' | grep -qi "^${DOMAIN_NAME}$"; then
    add_detail "PASS: ACM cert covers domain ($DOMAIN_NAME)."
  else
    add_warning "WARN: ACM cert SAN list does not visibly include $DOMAIN_NAME (check wildcard coverage)."
  fi
else
  add_warning "WARN: No ACM certificate ARN available to validate."
fi

# ---------- WAF association check ----------
# CloudFront WAFv2 resource ARN format:
# arn:aws:cloudfront::<account-id>:distribution/<distribution-id>
account_id="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")"
cf_resource_arn=""
if [[ -n "$account_id" ]]; then
  cf_resource_arn="arn:aws:cloudfront::${account_id}:distribution/${CF_DISTRIBUTION_ID}"
fi

if [[ "$REQUIRE_WAF_ASSOCIATION" == "true" ]]; then
  if [[ -n "$cf_resource_arn" ]]; then
    waf_assoc_arn="$(aws wafv2 get-web-acl-for-resource --resource-arn "$cf_resource_arn" --region "$CF_ACM_REGION" \
      --query "WebACL.ARN" --output text 2>/dev/null || echo "")"
    if [[ -n "$waf_assoc_arn" && "$waf_assoc_arn" != "None" ]]; then
      add_detail "PASS: WAF WebACL is associated with CloudFront."
      if [[ -n "$WAF_WEB_ACL_ARN" && "$waf_assoc_arn" != "$WAF_WEB_ACL_ARN" ]]; then
        add_warning "WARN: Associated WebACL ARN differs from WAF_WEB_ACL_ARN input (expected=$WAF_WEB_ACL_ARN, actual=$waf_assoc_arn)."
      fi

      # Warn if no managed rule groups detected
      managed_count="$(aws wafv2 get-web-acl --id "$(echo "$waf_assoc_arn" | awk -F/ '{print $NF}')" \
        --name "$(aws wafv2 get-web-acl-for-resource --resource-arn "$cf_resource_arn" --region "$CF_ACM_REGION" --query "WebACL.Name" --output text 2>/dev/null || echo "")" \
        --scope CLOUDFRONT --region "$CF_ACM_REGION" \
        --query "length(WebACL.Rules[?Statement.ManagedRuleGroupStatement!=null])" --output text 2>/dev/null || echo "0")"
      if [[ "$managed_count" != "0" ]]; then
        add_detail "PASS: WAF contains managed rule group(s) (count=$managed_count)."
      else
        add_warning "WARN: WAF has no managed rule groups detected (consider AWSManagedRules* baseline)."
      fi
    else
      add_failure "FAIL: No WAF WebACL associated with CloudFront distribution."
    fi
  else
    add_failure "FAIL: Could not build CloudFront resource ARN for WAF association check."
  fi
else
  add_detail "INFO: WAF association requirement disabled (REQUIRE_WAF_ASSOCIATION=false)."
fi

# ---------- Route53 alias checks ----------
# We verify A and AAAA records for the DOMAIN_NAME point to the CF distribution domain name
# and use CF alias zone id.
r53_rrsets="$(aws route53 list-resource-record-sets --hosted-zone-id "$ROUTE53_ZONE_ID" 2>/dev/null || true)"
if [[ -z "$r53_rrsets" ]]; then
  add_failure "FAIL: Unable to list Route53 record sets (zone=$ROUTE53_ZONE_ID)."
else
  add_detail "PASS: Route53 record sets retrieved (zone=$ROUTE53_ZONE_ID)."
fi

check_alias_record() {
  local type="$1"
  local name_fqdn="${DOMAIN_NAME}."
  local target="$cf_domain"

  # record may be root or with trailing dot
  local found_target
  found_target="$(aws route53 list-resource-record-sets --hosted-zone-id "$ROUTE53_ZONE_ID" \
    --query "ResourceRecordSets[?Type=='$type' && (Name=='$name_fqdn' || Name=='$DOMAIN_NAME')].AliasTarget.DNSName" \
    --output text 2>/dev/null || echo "")"

  local found_zone
  found_zone="$(aws route53 list-resource-record-sets --hosted-zone-id "$ROUTE53_ZONE_ID" \
    --query "ResourceRecordSets[?Type=='$type' && (Name=='$name_fqdn' || Name=='$DOMAIN_NAME')].AliasTarget.HostedZoneId" \
    --output text 2>/dev/null || echo "")"

  if [[ -z "$found_target" ]]; then
    add_failure "FAIL: Route53 $type alias record not found for $DOMAIN_NAME."
    return
  fi

  # Route53 returns targets with trailing dot
  if echo "$found_target" | tr '\t' '\n' | grep -qi "^${target}\.?$"; then
    add_detail "PASS: Route53 $type alias points to CloudFront ($target)."
  else
    add_failure "FAIL: Route53 $type alias does not point to CloudFront (expected=$target, actual=$found_target)."
  fi

  if echo "$found_zone" | tr '\t' '\n' | grep -q "^${CF_ROUTE53_ALIAS_ZONE_ID}$"; then
    add_detail "PASS: Route53 $type alias HostedZoneId is CloudFront ($CF_ROUTE53_ALIAS_ZONE_ID)."
  else
    add_warning "WARN: Route53 $type alias HostedZoneId is not CloudFront constant (expected=$CF_ROUTE53_ALIAS_ZONE_ID, actual=$found_zone)."
  fi
}

check_alias_record "A"
check_alias_record "AAAA"

# ---------- CloudFront logging checks ----------
logging_bucket="$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" \
  --query "Distribution.DistributionConfig.Logging.Bucket" --output text 2>/dev/null || echo "")"
logging_enabled="false"
if [[ -n "$logging_bucket" && "$logging_bucket" != "None" ]]; then
  logging_enabled="true"
  add_detail "PASS: CloudFront logging appears enabled (bucket=$logging_bucket)."
else
  if [[ "$REQUIRE_LOGGING" == "true" ]]; then
    add_failure "FAIL: CloudFront logging not enabled (DistributionConfig.Logging.Bucket missing)."
  else
    add_warning "WARN: CloudFront logging not enabled."
  fi
fi

if [[ -n "$LOG_BUCKET" ]]; then
  # CloudFront stores bucket as "bucket-name.s3.amazonaws.com"
  expected_cf_bucket="${LOG_BUCKET}.s3.amazonaws.com"
  if [[ "$logging_enabled" == "true" ]]; then
    if echo "$logging_bucket" | grep -qi "^${expected_cf_bucket}\.?$"; then
      add_detail "PASS: CloudFront logs bucket matches expected ($LOG_BUCKET)."
    else
      add_warning "WARN: CloudFront logs bucket differs (expected=$expected_cf_bucket, actual=$logging_bucket)."
    fi
  fi

  # Bucket existence + public access block
  if aws s3api head-bucket --bucket "$LOG_BUCKET" >/dev/null 2>&1; then
    add_detail "PASS: Log bucket exists ($LOG_BUCKET)."
    pab="$(aws s3api get-public-access-block --bucket "$LOG_BUCKET" \
      --query "PublicAccessBlockConfiguration" --output text 2>/dev/null || echo "")"
    if [[ -n "$pab" ]]; then
      add_detail "PASS: Log bucket has PublicAccessBlock configuration."
    else
      add_warning "WARN: Could not confirm PublicAccessBlock on log bucket."
    fi
  else
    add_failure "FAIL: Log bucket does not exist or not accessible ($LOG_BUCKET)."
  fi
else
  add_detail "INFO: LOG_BUCKET not provided; skipping S3 log bucket validations."
fi

# ---------- Origin SG checks (indirect enforcement of 'only via CloudFront') ----------
# We FAIL if origin SG allows 0.0.0.0/0 (or ::/0) on app ports.
# We PASS if we find NO world-open rules on those ports.
if [[ -n "$ORIGIN_SG_ID" ]]; then
  if aws ec2 describe-security-groups --group-ids "$ORIGIN_SG_ID" --region "$ORIGIN_REGION" >/dev/null 2>&1; then
    add_detail "PASS: Origin SG exists ($ORIGIN_SG_ID)."
  else
    add_failure "FAIL: Origin SG not found or not accessible ($ORIGIN_SG_ID)."
  fi

  IFS=',' read -r -a ports <<< "$APP_PORTS"
  world_open=false

  for p in "${ports[@]}"; do
    p="$(echo "$p" | tr -d ' ')"
    [[ -z "$p" ]] && continue

    v4="$(aws ec2 describe-security-groups --group-ids "$ORIGIN_SG_ID" --region "$ORIGIN_REGION" \
      --query "SecurityGroups[0].IpPermissions[?FromPort==\`${p}\` && ToPort==\`${p}\`].IpRanges[].CidrIp" \
      --output text 2>/dev/null || echo "")"
    v6="$(aws ec2 describe-security-groups --group-ids "$ORIGIN_SG_ID" --region "$ORIGIN_REGION" \
      --query "SecurityGroups[0].IpPermissions[?FromPort==\`${p}\` && ToPort==\`${p}\`].Ipv6Ranges[].CidrIpv6" \
      --output text 2>/dev/null || echo "")"

    if echo "$v4 $v6" | grep -Eq '(^| )0\.0\.0\.0/0( |$)|(^| )::/0( |$)'; then
      world_open=true
      add_failure "FAIL: Origin SG $ORIGIN_SG_ID allows port $p from the world (0.0.0.0/0 or ::/0)."
    else
      add_detail "PASS: Origin SG $ORIGIN_SG_ID is not world-open on port $p."
    fi

    # If you’re using CloudFront origin-facing prefix list, we can’t reliably detect it without
    # hardcoding prefix list IDs per region; we warn if no SG-to-SG and no CIDRs at all.
    src_sgs="$(aws ec2 describe-security-groups --group-ids "$ORIGIN_SG_ID" --region "$ORIGIN_REGION" \
      --query "SecurityGroups[0].IpPermissions[?FromPort==\`${p}\` && ToPort==\`${p}\`].UserIdGroupPairs[].GroupId" \
      --output text 2>/dev/null || echo "")"

    if [[ -z "$src_sgs" && -z "$v4" && -z "$v6" ]]; then
      add_warning "WARN: Origin SG $ORIGIN_SG_ID has no visible sources on port $p (check prefix lists / LB SG chaining)."
    fi
  done
else
  add_detail "INFO: ORIGIN_SG_ID not provided; origin reachability enforcement checks skipped."
fi

# ---------- Lab 2B (Cache correctness) — WARN-only checks ----------
# We warn if using legacy ForwardedValues instead of CachePolicyId/OriginRequestPolicyId.
cache_policy_id="$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" \
  --query "Distribution.DistributionConfig.DefaultCacheBehavior.CachePolicyId" --output text 2>/dev/null || echo "")"
forwarded_values="$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" \
  --query "Distribution.DistributionConfig.DefaultCacheBehavior.ForwardedValues" --output text 2>/dev/null || echo "")"

if [[ -n "$cache_policy_id" && "$cache_policy_id" != "None" ]]; then
  add_detail "PASS: DefaultCacheBehavior uses CachePolicyId (modern caching config)."
else
  if [[ -n "$forwarded_values" && "$forwarded_values" != "None" ]]; then
    add_warning "WARN: DefaultCacheBehavior appears to use legacy ForwardedValues (consider CachePolicyId for Lab 2B)."
  else
    add_warning "WARN: Could not determine caching configuration clearly (Lab 2B may require CachePolicyId)."
  fi
fi

# ---------- Determine overall ----------
overall_status="PASS"
overall_exit=0
if (( ${#failures[@]} > 0 )); then
  overall_status="FAIL"
  overall_exit=2
fi

warn_count=${#warnings[@]}
badge="$(badge_from "$overall_status" "$warn_count")"

echo "$badge" > "$BADGE_TXT"

# SLA clocks (persist first fail time; clear on pass)
mkdirp "$STATE_DIR"
first_seen_utc=""
last_seen_utc="$ts_now"

if [[ "$overall_status" == "FAIL" ]]; then
  if [[ -f "$STATE_FILE" ]]; then first_seen_utc="$(cat "$STATE_FILE" | tr -d '\n' || true)"; fi
  if [[ -z "$first_seen_utc" ]]; then first_seen_utc="$ts_now"; echo "$first_seen_utc" > "$STATE_FILE"; fi
else
  rm -f "$STATE_FILE" >/dev/null 2>&1 || true
fi

breach=false
due_utc=""
age_seconds=""
remaining_seconds=""

if [[ -n "$first_seen_utc" ]]; then
  first_epoch="$(iso_to_epoch "$first_seen_utc")"
  now_epoch="$(iso_to_epoch "$ts_now")"
  if [[ -n "$first_epoch" && -n "$now_epoch" ]]; then
    age_seconds="$(( now_epoch - first_epoch ))"
    sla_seconds="$(( SLA_HOURS * 3600 ))"
    due_epoch="$(( first_epoch + sla_seconds ))"
    due_utc="$(epoch_to_iso "$due_epoch")"
    if (( now_epoch > due_epoch )); then breach=true; remaining_seconds=0
    else remaining_seconds="$(( due_epoch - now_epoch ))"
    fi
  fi
fi

# Build JSON arrays safely (no jq required)
make_json_array() {
  if (( $# == 0 )); then echo "[]"; return; fi
  printf '%s\n' "$@" | json_escape | awk 'BEGIN{print "["} {printf "%s\"%s\"", (NR>1?",":""), $0} END{print "]"}'
}

details_json="$(make_json_array "${details[@]}")"
warnings_json="$(make_json_array "${warnings[@]}")"
failures_json="$(make_json_array "${failures[@]}")"

# Write combined JSON
cat > "$OUT_JSON" <<EOF
{
  "schema_version": "2.0",
  "gate": "lab2_all_gates",
  "timestamp_utc": "$(now_utc)",
  "badge": "$badge",
  "status": "$overall_status",
  "exit_code": $overall_exit,

  "inputs": {
    "origin_region": "$(echo "$ORIGIN_REGION" | json_escape)",
    "cloudfront_distribution_id": "$(echo "$CF_DISTRIBUTION_ID" | json_escape)",
    "domain_name": "$(echo "$DOMAIN_NAME" | json_escape)",
    "route53_zone_id": "$(echo "$ROUTE53_ZONE_ID" | json_escape)",
    "acm_cert_arn": "$(echo "$ACM_CERT_ARN" | json_escape)",
    "waf_web_acl_arn": "$(echo "$WAF_WEB_ACL_ARN" | json_escape)",
    "log_bucket": "$(echo "$LOG_BUCKET" | json_escape)",
    "origin_sg_id": "$(echo "$ORIGIN_SG_ID" | json_escape)",
    "app_ports": "$(echo "$APP_PORTS" | json_escape)"
  },

  "observed": {
    "caller_arn": "$(echo "$caller_arn" | json_escape)",
    "cloudfront_domain": "$(echo "$cf_domain" | json_escape)",
    "cloudfront_status": "$(echo "$cf_status" | json_escape)",
    "cloudfront_enabled": "$(echo "$cf_enabled" | json_escape)",
    "cloudfront_aliases": "$(echo "$cf_aliases" | json_escape)",
    "viewer_cert_source": "$(echo "$viewer_cert_source" | json_escape)",
    "viewer_acm_arn": "$(echo "$viewer_acm_arn" | json_escape)",
    "minimum_tls": "$(echo "$min_tls" | json_escape)",
    "logging_bucket": "$(echo "$logging_bucket" | json_escape)",
    "cache_policy_id": "$(echo "$cache_policy_id" | json_escape)"
  },

  "rollup": {
    "details": $details_json,
    "warnings": $warnings_json,
    "failures": $failures_json
  },

  "clocks": {
    "first_seen_utc": "$(echo "${first_seen_utc:-}" | json_escape)",
    "last_seen_utc": "$(echo "$last_seen_utc" | json_escape)"
  },
  "sla": {
    "target_hours": $SLA_HOURS,
    "due_utc": "$(echo "${due_utc:-}" | json_escape)",
    "breached": $breach,
    "age_seconds": "$(echo "${age_seconds:-}" | json_escape)",
    "remaining_seconds": "$(echo "${remaining_seconds:-}" | json_escape)"
  },

  "artifacts": {
    "badge_txt": "$(echo "$BADGE_TXT" | json_escape)",
    "pr_comment_md": "$(echo "$PR_COMMENT_MD" | json_escape)"
  }
}
EOF

# Write PR comment
cat > "$PR_COMMENT_MD" <<EOF
### SEIR Lab 2 Gate Result: **$badge** ($overall_status)

**Domain:** \`$DOMAIN_NAME\`  
**CloudFront:** \`$CF_DISTRIBUTION_ID\` (domain: \`$cf_domain\`)  
**WAF required:** \`$REQUIRE_WAF_ASSOCIATION\`  
**Logging required:** \`$REQUIRE_LOGGING\`  
**Origin SG:** \`${ORIGIN_SG_ID:-"(not provided)"}\`  

**SLA**
- target: \`${SLA_HOURS}h\`
- first_seen: \`${first_seen_utc:-}\`
- due: \`${due_utc:-}\`
- breached: \`$breach\`

**Failures (fix in order)**
$(if (( ${#failures[@]} == 0 )); then echo "- (none)"; else for f in "${failures[@]}"; do echo "- $f"; done; fi)

**Warnings**
$(if (( ${#warnings[@]} == 0 )); then echo "- (none)"; else for w in "${warnings[@]}"; do echo "- $w"; done; fi)

> Reminder: Hennessy does not fix Route53 alias records. Evidence does.
EOF

# Optional jq summary (nice for students)
if have_cmd jq; then
  echo ""
  echo "=== jq summary ==="
  jq -r '
    "SEIR Lab 2 Gate Summary",
    "----------------------",
    ("Badge:  " + .badge),
    ("Status: " + .status),
    "",
    "Failures:",
    (if (.rollup.failures|length)==0 then "  (none)" else (.rollup.failures[] | "  - " + .) end),
    "",
    "Warnings:",
    (if (.rollup.warnings|length)==0 then "  (none)" else (.rollup.warnings[] | "  - " + .) end)
  ' "$OUT_JSON" || true
  echo ""
else
  add_detail "INFO: jq not installed; skipping pretty summary."
fi

# Console summary
echo ""
echo "===== SEIR Lab 2 Gate Summary ====="
echo "BADGE:  $badge  (written to $BADGE_TXT)"
echo "RESULT: $overall_status"
echo "JSON:   $OUT_JSON"
echo "PR:     $PR_COMMENT_MD"
echo "==================================="
echo ""

exit "$overall_exit"