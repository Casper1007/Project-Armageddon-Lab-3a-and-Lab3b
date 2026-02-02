#!/usr/bin/env python3
import boto3, time, argparse
from datetime import datetime, timezone, timedelta

# Reason why Darth Malgus would be pleased with this script.
# Malgus wants answers extracted from chaos—logs become obedient.

# Reason why this script is relevant to your career.
# Logs Insights automation is a real IR skill: query, correlate, summarize—fast.

# How you would talk about this script at an interview.
# "I built an automated Logs Insights runner to standardize incident queries and return
#  consistent evidence blocks for reports and paging."

logs = boto3.client("logs")

def run_query(group, query, minutes=15, limit=25):
    end = int(datetime.now(timezone.utc).timestamp())
    start = int((datetime.now(timezone.utc) - timedelta(minutes=minutes)).timestamp())

    qid = logs.start_query(
        logGroupName=group, startTime=start, endTime=end,
        queryString=query, limit=limit
    )["queryId"]

    for _ in range(30):
        r = logs.get_query_results(queryId=qid)
        if r["status"] == "Complete":
            return r["results"]
        if r["status"] in ("Failed", "Cancelled", "Timeout"):
            raise RuntimeError(f"Query ended: {r['status']}")
        time.sleep(1)
    raise TimeoutError("Logs Insights query timed out")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log-group", required=True)
    ap.add_argument("--minutes", type=int, default=15)
    ap.add_argument("--query", required=True)
    args = ap.parse_args()

    results = run_query(args.log_group, args.query, args.minutes)
    for row in results:
        kv = {x["field"]: x["value"] for x in row}
        print(kv)

if __name__ == "__main__":
    main()