#!/usr/bin/env python3
import boto3, json, os

# Reason why Darth Malgus would be pleased with this script.
# Drift is rebellion—Malgus crushes it before it becomes a civil war.

# Reason why this script is relevant to your career.
# Config drift is a top cause of outages; checking and proving drift is SRE/SEC gold.

# How you would talk about this script at an interview.
# "I built a drift detector that validates secret/config consistency and prevents silent
#  mismatches from becoming production incidents."

ssm = boto3.client("ssm")
secrets = boto3.client("secretsmanager")

SSM_PATH = os.getenv("SSM_PATH", "/lab/db/")
SECRET_ID = os.getenv("SECRET_ID", "chewbacca/rds/mysql")

def main():
    params = ssm.get_parameters_by_path(Path=SSM_PATH, Recursive=True, WithDecryption=True)["Parameters"]
    p = {x["Name"]: x["Value"] for x in params}

    s = secrets.get_secret_value(SecretId=SECRET_ID)["SecretString"]
    sec = json.loads(s)

    checks = {
        "endpoint": (p.get(f"{SSM_PATH}endpoint"), sec.get("host")),
        "port": (p.get(f"{SSM_PATH}port"), str(sec.get("port")) if sec.get("port") else None),
        "dbname": (p.get(f"{SSM_PATH}name"), sec.get("dbname")),
        "username": (p.get(f"{SSM_PATH}username"), sec.get("username")),
    }

    ok = True
    for k, (a, b) in checks.items():
        if a and b and a != b:
            ok = False
            print(f"DRIFT: {k} SSM={a} SECRET={b}")
        else:
            print(f"OK: {k}")

    print("\nResult:", "PASS (no drift)" if ok else "FAIL (drift detected)")

if __name__ == "__main__":
    main()