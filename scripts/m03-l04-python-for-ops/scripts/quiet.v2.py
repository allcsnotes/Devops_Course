#!/usr/bin/env python3
# quiet.py: check Course Copilot, and say so when it fails
import json
import sys
import urllib.error
import urllib.request

problems = 0
try:
    resp = urllib.request.urlopen("http://copilot-01:8000/health", timeout=3)
    if json.load(resp)["status"] != "ok":
        problems += 1
except urllib.error.URLError as e:
    print(f"copilot: {e}", file=sys.stderr)
    problems += 1
print(f"copilot: {problems} problem(s)")
sys.exit(1 if problems else 0)
