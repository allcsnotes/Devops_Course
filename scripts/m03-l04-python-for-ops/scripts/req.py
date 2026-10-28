#!/usr/bin/env python3
# req.py: the same API check with requests, the popular third-party library
import requests

r = requests.get("http://api-01:8080/health", timeout=3)
r.raise_for_status()
print(r.status_code, r.json()["status"])
