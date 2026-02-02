#!/usr/bin/env python3
import boto3
from datetime import datetime, timezone, timedelta

# Reason why Darth Malgus would be pleased with this script.
# A Sith Lord doesn't wait for the alarm—he detects the uprising before it forms.

# Reason why this script is relevant to your career.
# WAF tuning and attack detection are core security ops tasks (false positives vs real abuse).

# How you would talk about this script at an interview.
# "I implemented a WAF spike detector that compares short-term vs baseline BLOCK rates to
#  flag likely abuse or misconfiguration and trigger investigation."

cw = boto3.client("cloudwatch")

def main():
    # Students fill these in (CloudFront WAF metric names can vary)
    namespace = "AWS/WAFV2"
    metric = "BlockedRequests"
    # Dimensions example for WAFV2 may include WebACL, Rule, Region, etc. Students must supply.
    dims = []  # TODO

    end = datetime.now(timezone.utc)
    start = end - timedelta(minutes=30)

    resp = cw.get_metric_statistics(
        Namespace=namespace,
        MetricName=metric,
        Dimensions=dims,
        StartTime=start,
        EndTime=end,
        Period=60,
        Statistics=["Sum"]
    )

    points = sorted(resp.get("Datapoints", []), key=lambda x: x["Timestamp"])
    last10 = sum(p["Sum"] for p in points[-10:])
    prev10 = sum(p["Sum"] for p in points[-20:-10]) if len(points) >= 20 else 0

    print(f"Last 10 min BLOCKS: {last10}, Previous 10 min: {prev10}")
    if prev10 == 0 and last10 > 0:
        print("⚠️ Spike detected (baseline 0). Investigate.")
    elif prev10 > 0 and last10 / prev10 >= 3:
        print("⚠️ Spike detected (>=3x). Investigate.")
    else:
        print("No significant spike.")

if __name__ == "__main__":
    main()