#!/usr/bin/env python3
import boto3
from datetime import datetime, timezone, timedelta

# Reason why Darth Malgus would be pleased with this script.
# Malgus enjoys crushing enemies—but he hates wasting credits on sloppy operations.

# Reason why this script is relevant to your career.
# Cost-aware engineering is modern DevOps/SRE reality: guardrails prevent surprise bills.

# How you would talk about this script at an interview.
# "I wrote a lightweight guardrail that flags risky operational actions (like over-broad invalidations)
#  and correlates them with traffic/log surges."

cf = boto3.client("cloudfront")

def main():
    # Students provide distribution id
    dist_id = "REPLACE_ME"
    resp = cf.list_invalidations(DistributionId=dist_id, MaxItems="10")
    items = resp.get("InvalidationList", {}).get("Items", [])
    print(f"Recent invalidations for {dist_id}: {len(items)}")
    for inv in items:
        print(inv["Id"], inv["Status"], inv["CreateTime"])

if __name__ == "__main__":
    main()