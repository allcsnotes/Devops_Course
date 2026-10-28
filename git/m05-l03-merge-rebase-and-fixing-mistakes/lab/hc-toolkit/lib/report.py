#!/usr/bin/env python3
"""report.py: turns hc results (on stdin) into JSON.

  report.py json STATUS            print the results as JSON
  report.py alert URL OLD NEW      POST a state change to a chat webhook
"""
import json
import socket
import sys
import urllib.error
import urllib.request


def main():
    mode, *args = sys.argv[1:]
    checks = []
    for line in sys.stdin.read().splitlines():
        sev, check, detail = line.split("\t")
        checks.append({"severity": sev, "check": check, "detail": detail})
    host = socket.gethostname()
    if mode == "json":
        report = {"host": host, "status": args[0], "checks": checks}
        print(json.dumps(report, indent=2))
        return 0

    url, old, new = args
    problems = [f"{c['check']}: {c['detail']}" for c in checks
                if c["severity"] != "OK"]
    summary = "; ".join(problems) if problems else "all checks OK again"
    payload = {"text": f"[{new}] {host}: {summary}", "host": host,
               "from": old, "to": new, "problems": problems}
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            print(f"alert sent: {old} -> {new}, HTTP {resp.status}")
    except (urllib.error.URLError, TimeoutError) as e:
        print(f"alert failed: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
