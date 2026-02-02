#!/usr/bin/env python3
import boto3, json

# Reason why Darth Malgus would be pleased with this script.
# Malgus wants proof, not opinions: "Show me the database lives ONLY in Tokyo."
# Reason why this script is relevant to your career.
# Auditors demand evidence bundles. Automating compliance proofs is real-world SRE/SEC work.
# How you would talk about this script at an interview.
# "I automated data residency verification by checking RDS inventory across regions and exporting an audit artifact."

def list_rds(region):
    rds = boto3.client("rds", region_name=region)
    resp = rds.describe_db_instances()
    out = []
    for d in resp.get("DBInstances", []):
        out.append({
            "region": region,
            "id": d["DBInstanceIdentifier"],
            "az": d.get("AvailabilityZone"),
            "endpoint": d.get("Endpoint", {}).get("Address")
        })
    return out

def main():
    tokyo = list_rds("ap-northeast-1")
    sp    = list_rds("sa-east-1")

    evidence = {
        "tokyo_rds": tokyo,
        "saopaulo_rds": sp,
        "assertion": "PASS" if len(tokyo) > 0 and len(sp) == 0 else "FAIL"
    }
    print(json.dumps(evidence, indent=2))

if __name__ == "__main__":
    main()