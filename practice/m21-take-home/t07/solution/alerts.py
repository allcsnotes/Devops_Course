"""alerts.py: print Prometheus's active alerts as one line each (state, name, labels, since)."""
import json
import sys
import urllib.request

url = sys.argv[1] if len(sys.argv) > 1 else "http://prometheus:9090"
data = json.load(urllib.request.urlopen(url + "/api/v1/alerts", timeout=5))["data"]["alerts"]
for a in sorted(data, key=lambda a: a["labels"]["alertname"]):
    l = a["labels"]
    print(f'{a["state"]:8} {l["alertname"]:28} severity={l["severity"]:7} since {a["activeAt"][11:19]}Z')
if not data:
    print("no active alerts")
