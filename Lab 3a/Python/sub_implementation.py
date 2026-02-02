def cmd_collect_evidence(args):
    cw = boto3.client("cloudwatch", region_name=args.region) if args.region else boto3.client("cloudwatch")
    logs = boto3.client("logs", region_name=args.region) if args.region else boto3.client("logs")
    ssm = boto3.client("ssm", region_name=args.region) if args.region else boto3.client("ssm")
    secrets = boto3.client("secretsmanager", region_name=args.region) if args.region else boto3.client("secretsmanager")

    incident_id = args.incident_id or f"IR-{utc_now().strftime('%Y%m%d-%H%M%S')}"
    end = utc_now()
    start = end - timedelta(minutes=args.minutes)

    evidence = {
        "incident_id": incident_id,
        "time_window_utc": {
            "start": start.isoformat(),
            "end": end.isoformat()
        }
    }

    # --- Alarms ---
    alarms = cw.describe_alarms(StateValue="ALARM", MaxRecords=25).get("MetricAlarms", [])
    evidence["alarms"] = [
        {
            "name": a["AlarmName"],
            "metric": a.get("MetricName"),
            "namespace": a.get("Namespace"),
            "reason": a.get("StateReason"),
            "updated": str(a.get("StateUpdatedTimestamp"))
        }
        for a in alarms
    ]

    # --- Logs ---
    evidence["logs"] = {}

    if args.app_log_group:
        evidence["logs"]["app_errors"] = run_logs_query(
            logs,
            args.app_log_group,
            'fields @timestamp, @message | filter @message like /ERROR|Exception/ | sort @timestamp desc',
            args.minutes
        )

        evidence["logs"]["app_rate"] = run_logs_query(
            logs,
            args.app_log_group,
            'stats count() as errors by bin(1m)',
            args.minutes
        )

    if args.waf_log_group:
        evidence["logs"]["waf_actions"] = run_logs_query(
            logs,
            args.waf_log_group,
            'stats count() as hits by action',
            args.minutes
        )

        evidence["logs"]["waf_top_ips"] = run_logs_query(
            logs,
            args.waf_log_group,
            'stats count() as hits by httpRequest.clientIp | sort hits desc | limit 10',
            args.minutes
        )

    # --- Config sources (metadata only) ---
    ssm_meta = {}
    token = None
    while True:
        r = ssm.get_parameters_by_path(
            Path=args.ssm_path,
            Recursive=True,
            WithDecryption=False,
            NextToken=token
        ) if token else ssm.get_parameters_by_path(
            Path=args.ssm_path,
            Recursive=True,
            WithDecryption=False
        )
        for p in r.get("Parameters", []):
            ssm_meta[p["Name"]] = {"type": p["Type"]}
        token = r.get("NextToken")
        if not token:
            break

    sec = secrets.get_secret_value(SecretId=args.secret_id)
    sec_meta = {"secret_id": args.secret_id, "has_rotation": bool(sec.get("RotationEnabled"))}

    evidence["config_sources"] = {
        "ssm_meta": ssm_meta,
        "secrets_meta": sec_meta
    }

    # --- Write file ---
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(evidence, f, indent=2)

    print(f"[MALGUS] Evidence bundle written: {args.out}")