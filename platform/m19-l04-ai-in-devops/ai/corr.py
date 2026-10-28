"""corr.py: classic AIOps event correlation, no AI model. Statistics and a service map only.
  python3 corr.py incident/alerts.json incident/deploys.log
1. time: alerts that start within WINDOW seconds of each other belong together
2. topology: alerts on services that call each other belong together (the map below)
3. origin: the deepest alerting service on the call path is the probable origin; its callers are victims
4. change: deploys in the hour before the first alert, on the incident's services
"""
import json, sys
from collections import Counter, defaultdict
from datetime import datetime, timezone, timedelta

WINDOW = 300
CALLS = {"storefront-bff": ["catalog-api"], "course-copilot": ["catalog-api"], "catalog-api": ["postgres"]}
IST = timezone(timedelta(hours=5, minutes=30))
ts = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00"))
hms = lambda d: d.astimezone(IST).strftime("%H:%M:%S")

alerts = [a for a in json.load(open(sys.argv[1])) if a["status"]["state"] == "active"]
alerts.sort(key=lambda a: a["startsAt"])
print(f"{len(alerts)} firing alerts, {len(Counter(a['labels']['alertname'] for a in alerts))} alert names, "
      f"{len({a['labels'].get('service') for a in alerts})} services")

# 1 + 2: union-find over alerts: same time window AND (same service or services that call each other)
par = list(range(len(alerts)))
find = lambda i: i if par[i] == i else find(par[i])
linked = lambda s, t: s == t or t in CALLS.get(s, []) or s in CALLS.get(t, [])
for i in range(len(alerts)):
    for j in range(i):
        a, b = alerts[i], alerts[j]
        if abs((ts(a["startsAt"]) - ts(b["startsAt"])).total_seconds()) <= WINDOW and \
                linked(a["labels"].get("service"), b["labels"].get("service")):
            par[find(i)] = find(j)
groups = defaultdict(list)
for i, a in enumerate(alerts):
    groups[find(i)].append(a)
print(f"-> {len(groups)} incident{'s' if len(groups) != 1 else ''}\n")

deploys = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
for n, g in enumerate(groups.values(), 1):
    t0 = ts(g[0]["startsAt"])
    svcs = Counter(a["labels"].get("service") for a in g)
    # origin: an alerting service none of whose callees alert
    origin = [s for s in svcs if not any(c in svcs for c in CALLS.get(s, []))]
    print(f"incident {n}: {len(g)} alerts, first at {hms(t0)}, last at {hms(ts(g[-1]['startsAt']))}")
    for s, c in svcs.most_common():
        role = "probable origin" if s in origin else "victim (calls " + ", ".join(CALLS.get(s, [])) + ")"
        names = Counter(a["labels"]["alertname"] for a in g if a["labels"].get("service") == s)
        print(f"  {s:15} {c:2} alerts  {role}")
        print(f"  {'':15} " + ", ".join(f"{k} x{v}" for k, v in names.most_common()))
    print("  changes in the hour before the first alert:")
    for d in deploys:
        dt = datetime.fromtimestamp(d["start"], IST)
        if timedelta(0) <= t0 - dt <= timedelta(hours=1):
            mark = "  <- on the probable origin" if d["service"] in origin else ""
            print(f"    {dt.strftime('%H:%M:%S')}  {d['service']} {d['version']} by {d['by']}"
                  f"  ({int((t0 - dt).total_seconds())} s before){mark}")
