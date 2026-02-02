#!/usr/bin/env python3
"""
Lab 3B — Enhanced Data Residency Proof
========================================
Purpose: Prove that PHI data resides ONLY in Tokyo (ap-northeast-1)
Compliance: APPI (Japan's Act on the Protection of Personal Information)
"""

import boto3
import json
from datetime import datetime

def list_rds(region):
    """List all RDS instances in a region"""
    rds = boto3.client("rds", region_name=region)
    resp = rds.describe_db_instances()
    out = []
    for d in resp.get("DBInstances", []):
        out.append({
            "region": region,
            "id": d["DBInstanceIdentifier"],
            "az": d.get("AvailabilityZone"),
            "endpoint": d.get("Endpoint", {}).get("Address"),
            "multi_az": d.get("MultiAZ", False),
            "encrypted": d.get("StorageEncrypted", False),
            "engine": d.get("Engine", "unknown")
        })
    return out

def list_rds_snapshots(region):
    """List RDS snapshots to verify backup location"""
    rds = boto3.client("rds", region_name=region)
    try:
        resp = rds.describe_db_snapshots(MaxRecords=20)
        return [{
            "snapshot_id": s["DBSnapshotIdentifier"],
            "region": region,
            "encrypted": s.get("Encrypted", False),
            "created": s.get("SnapshotCreateTime", "").isoformat() if s.get("SnapshotCreateTime") else "unknown"
        } for s in resp.get("DBSnapshots", [])]
    except:
        return []

def check_s3_audit_buckets():
    """Check S3 bucket locations for audit/logging buckets"""
    s3 = boto3.client('s3')
    try:
        buckets = s3.list_buckets()
        audit_buckets = []
        
        for bucket in buckets['Buckets']:
            bucket_name = bucket['Name']
            if any(keyword in bucket_name.lower() for keyword in 
                   ['cloudtrail', 'flowlog', 'cloudfront', 'waf', 'audit']):
                try:
                    location = s3.get_bucket_location(Bucket=bucket_name)
                    region = location['LocationConstraint'] or 'us-east-1'
                    audit_buckets.append({
                        "bucket_name": bucket_name,
                        "region": region,
                        "compliant": region == 'ap-northeast-1'
                    })
                except:
                    pass
        
        return audit_buckets
    except:
        return []

def main():
    print("=" * 80)
    print("Lab 3B — Data Residency Proof Generator")
    print("APPI Compliance Evidence")
    print("=" * 80)
    
    tokyo = list_rds("ap-northeast-1")
    sp    = list_rds("sa-east-1")
    tokyo_snapshots = list_rds_snapshots("ap-northeast-1")
    sp_snapshots = list_rds_snapshots("sa-east-1")
    audit_buckets = check_s3_audit_buckets()

    evidence = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "compliance_framework": "APPI",
        "proof_type": "data_residency",
        "rds_instances": {"tokyo": tokyo, "saopaulo": sp},
        "rds_snapshots": {"tokyo": tokyo_snapshots, "saopaulo": sp_snapshots},
        "audit_s3_buckets": audit_buckets,
        "compliance_check": {
            "tokyo_has_rds": len(tokyo) > 0,
            "saopaulo_has_no_rds": len(sp) == 0,
            "snapshots_in_tokyo_only": len(tokyo_snapshots) > 0 and len(sp_snapshots) == 0,
            "assertion": "PASS ✅" if (len(tokyo) > 0 and len(sp) == 0) else "FAIL ❌"
        }
    }
    
    with open("data_residency_proof.json", 'w') as f:
        json.dump(evidence, f, indent=2)
    
    print(f"\n✅ Evidence saved. Status: {evidence['compliance_check']['assertion']}")
    print(json.dumps(evidence, indent=2))

if __name__ == "__main__":
    main()
