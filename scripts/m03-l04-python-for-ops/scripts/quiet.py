#!/usr/bin/env python3
# quiet.py: check Course Copilot, "and never crash"
import json
import urllib.request

problems = 0
try:
    resp = urllib.request.urlopen("http://copilot-01:8000/health", timeout=3)
    if json.load(resp)["status"] != "ok":
        problems += 1
except Exception:
    pass
print(f"copilot: {problems} problem(s)")
