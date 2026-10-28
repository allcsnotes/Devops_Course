"""anomaly.py START END: the simplest statistical anomaly detector, a z-score, computed by Prometheus itself.
z = (now - baseline mean) / baseline standard deviation, baseline = the 30 minutes before, ending 5 minutes ago.
Prints, per service, the first moment |z| > 3 between START and END (HH:MM, today, IST) and the peak."""
import json, sys, time, urllib.parse, urllib.request
from datetime import datetime, timedelta, timezone

IST = timezone(timedelta(hours=5, minutes=30))
X = "service:http_p95:1m"
Q = f"({X} - avg_over_time({X}[30m] offset 5m)) / stddev_over_time({X}[30m] offset 5m)"
day = datetime.now(IST).date()
at = lambda s: datetime.combine(day, datetime.strptime(s, "%H:%M").time(), IST).timestamp()
u = "http://prometheus:9090/api/v1/query_range?" + urllib.parse.urlencode(
    {"query": Q, "start": at(sys.argv[1]), "end": at(sys.argv[2]), "step": "15s"})
res = json.load(urllib.request.urlopen(u))["data"]["result"]
print("z-score of p95 latency per service, baseline 30 min, threshold |z| > 3")
for r in sorted(res, key=lambda r: r["metric"]["service"]):
    pts = [(float(t), float(v)) for t, v in r["values"]]
    hit = next(((t, v) for t, v in pts if abs(v) > 3), None)
    peak = max(pts, key=lambda p: p[1])
    hh = lambda t: datetime.fromtimestamp(t, IST).strftime("%H:%M:%S")
    print(f"  {r['metric']['service']:15} " + (f"anomaly from {hh(hit[0])} (z = {hit[1]:.1f})" if hit else "no anomaly")
          + f", peak z = {peak[1]:.1f} at {hh(peak[0])}")
