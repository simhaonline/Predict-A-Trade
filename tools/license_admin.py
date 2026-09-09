#!/usr/bin/env python3
"""Predict-A-Trade license admin — create/list/revoke licenses in the dockerized Postgres.

Raw license keys are shown ONCE at creation; only SHA256 hashes are stored.

Usage:
  license_admin.py create [--key KEY] [--plan monthly] [--max-activations 2] [--days 30]
  license_admin.py list [--limit 20]
  license_admin.py revoke --key KEY
  license_admin.py events [--limit 20]

Requires the license-server stack to be running (docker exec access to its postgres).
"""
import argparse
import hashlib
import json
import secrets
import subprocess
import sys

CONTAINER = "license-server-postgres-1"


def psql(sql: str) -> str:
    cmd = ["docker", "exec", CONTAINER, "psql", "-U", "pat_license", "-d", "pat_license",
           "-At", "-c", sql]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"psql failed: {r.stderr.strip()}")
    return r.stdout.strip()


def gen_key() -> str:
    return "PAT-" + "-".join(secrets.token_hex(2).upper() for _ in range(4))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("create")
    c.add_argument("--key", default=None, help="supply a key, or one is generated")
    c.add_argument("--plan", default="monthly")
    c.add_argument("--max-activations", type=int, default=2)
    c.add_argument("--days", type=int, default=30)

    l = sub.add_parser("list")
    l.add_argument("--limit", type=int, default=20)

    r = sub.add_parser("revoke")
    r.add_argument("--key", required=True)

    e = sub.add_parser("events")
    e.add_argument("--limit", type=int, default=20)

    args = ap.parse_args()

    if args.cmd == "create":
        key = args.key or gen_key()
        h = hashlib.sha256(key.encode()).hexdigest()
        out = psql(f"""INSERT INTO licenses (license_key_hash, status, plan, max_activations, expires_at)
VALUES ('{h}', 'active', '{args.plan}', {args.max_activations}, NOW() + INTERVAL '{args.days} days')
RETURNING id, expires_at;""")
        print(json.dumps({"license_key": key, "id": out.split("|")[0], "expires_at": out.split("|")[1],
                          "plan": args.plan, "max_activations": args.max_activations}, indent=2))
        print("SAVE THIS KEY NOW - it is stored only as a SHA256 hash and cannot be recovered.", file=sys.stderr)
    elif args.cmd == "list":
        print(psql(f"""SELECT id, status, plan, max_activations,
ROUND(extract(epoch FROM (expires_at - NOW()))/86400) || 'd' AS expires_in,
(SELECT COUNT(*) FROM activations a WHERE a.license_id = l.id) AS seats
FROM licenses l ORDER BY created_at DESC LIMIT {args.limit};"""))
    elif args.cmd == "revoke":
        h = hashlib.sha256(args.key.encode()).hexdigest()
        n = psql(f"UPDATE licenses SET status='revoked' WHERE license_key_hash='{h}' RETURNING id;")
        print("revoked: " + n if n else "no license matched that key")
    elif args.cmd == "events":
        print(psql(f"SELECT created_at, COALESCE(license_id::text,'-'), event_type, ip_address "
                   f"FROM license_events ORDER BY id DESC LIMIT {args.limit};"))


if __name__ == "__main__":
    main()