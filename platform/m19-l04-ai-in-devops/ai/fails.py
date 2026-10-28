"""fails.py FROM TO: requests and failures per 10 seconds, from the load generator's request log (lab/runs/r1.csv).
FROM and TO are HH:MM:SS today, IST."""
import csv, sys, time
from datetime import datetime, timedelta, timezone
IST = timezone(timedelta(hours=5, minutes=30))
day = datetime.now(IST).replace(hour=0, minute=0, second=0, microsecond=0)   # today, IST (the lab clock)
at = lambda s: (day + timedelta(hours=int(s[:2]), minutes=int(s[3:5]), seconds=int(s[6:8]))).timestamp()
a, b = at(sys.argv[1]), at(sys.argv[2]); bins = {}
for r in csv.reader(open("/work/lab/runs/r1.csv")):
    t = float(r[0])
    if a <= t < b:
        k = int((t - a) // 10); n, f = bins.get(k, (0, 0)); bins[k] = (n + 1, f + (r[3] == "0" or int(r[3]) >= 500))
for k in sorted(bins):
    n, f = bins[k]; print(f"{time.strftime('%H:%M:%S', time.localtime(a + 10 * k))}  {n:3} requests  {f:3} failed  {100 * f / n:3.0f}%")
