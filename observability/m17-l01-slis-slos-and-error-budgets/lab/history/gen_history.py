"""gen_history.py END_EPOCH OUT.om : 30 days of SYNTHETIC history for the catalog API, for backfilling with promtool.

The lab can't wait 30 days, so this script writes the counters the API would have exposed, one sample a minute, in
OpenMetrics format, ending at END_EPOCH (when the live lab starts). `promtool tsdb create-blocks-from openmetrics`
turns the file into TSDB blocks. Labels match the live scrape (job="api", instance="api:8080"), so the live
counters continue the same series. Seeded random numbers, so the file is reproducible.

Traffic: about 10 requests a second with a daily wave (busier in the Indian evening). Background errors: 0.005 %.
Two incidents this month:
  2026-10-06 21:40 IST, 20 min: a migration holds a lock (the failure of M16-L01, but longer), 96.5 % fail
  2026-10-14 18:39 IST, 4 min 40 s: a bad deploy, every request fails, then a rollback (as in M16-L03)
"""
import math, random, sys
from datetime import datetime, timezone, timedelta

IST = timezone(timedelta(hours=5, minutes=30))
END = int(sys.argv[1]) // 60 * 60
OUT = sys.argv[2]
START = END - (30 * 86400 + 6 * 3600)                     # 30 days + 6 h, so every window is full
# The video was recorded with END = 2026-10-21 21:22 IST, which put the incidents on 2026-10-06 21:40 and
# 2026-10-14 18:39. They are placed relative to END, so the same story fits inside YOUR 30-day window.
RECORDED_END = datetime(2026, 10, 21, 21, 22, tzinfo=IST)
INCIDENTS = [(datetime(2026, 10, 6, 21, 40, tzinfo=IST), 20 * 60, 0.965),
             (datetime(2026, 10, 14, 18, 39, tzinfo=IST), 280, 1.0)]
SHIFT = END - int(RECORDED_END.timestamp())
INC = [(int(d.timestamp()) + SHIFT, int(d.timestamp()) + SHIFT + s, p) for d, s, p in INCIDENTS]
LE = ["0.005", "0.01", "0.025", "0.05", "0.1", "0.25", "0.5", "1.0", "2.5", "5.0"]
OK_CDF = [0.70, 0.92, 0.985, 0.995, 0.9985, 0.9995, 0.9999, 1, 1, 1]   # healthy latency, cumulative
BAD_CDF = [0, 0, 0, 0, 0, 0, 0.02, 0.55, 0.97, 1]                      # failing requests: pool waits, timeouts
rnd = random.Random(171)
B = 'job="api",instance="api:8080",route="/api/courses"'

series = {f'http_requests_total{{{B},status="{s}"}}': [] for s in ("200", "500", "503")}
for le in LE + ["+Inf"]:
    series[f'http_request_duration_seconds_bucket{{{B},le="{le}"}}'] = []
series[f'http_request_duration_seconds_count{{{B}}}'] = []
series[f'http_request_duration_seconds_sum{{{B}}}'] = []
tot = {k: 0.0 for k in series}
keys = list(series)

for ts in range(START, END + 1, 60):
    hour = datetime.fromtimestamp(ts, IST).hour + datetime.fromtimestamp(ts, IST).minute / 60
    rate = 10 + 2.5 * math.sin((hour - 14) / 24 * 2 * math.pi)            # peak about 20:00 IST
    n = max(0, int(rnd.gauss(rate * 60, math.sqrt(rate * 60))))
    p_bad = 0.00005
    for a, b, p in INC:
        if a <= ts < b:
            p_bad = p
    bad = sum(1 for _ in range(n) if rnd.random() < p_bad) if p_bad < 0.5 else n - sum(1 for _ in range(n) if rnd.random() < 1 - p_bad)
    good = n - bad
    b503 = round(bad * 0.87) if p_bad > 0.5 else rnd.choice([0, bad])
    tot[keys[0]] += good; tot[keys[1]] += bad - b503; tot[keys[2]] += b503
    for i, le in enumerate(LE):
        tot[keys[3 + i]] += round(good * OK_CDF[i]) + round(bad * BAD_CDF[i])
    tot[keys[13]] += n; tot[keys[14]] += n
    tot[keys[15]] += good * 0.004 + bad * 1.2
    for k in keys:
        series[k].append((tot[k], ts))

with open(OUT, "w") as f:
    f.write("# TYPE http_requests counter\n")
    for k in keys:                       # one series after another, each in time order
        for v, ts in series[k]:
            f.write(f"{k} {v:.0f} {ts}\n" if v == int(v) else f"{k} {v:.3f} {ts}\n")
    f.write("# EOF\n")
print("wrote", OUT, "from", datetime.fromtimestamp(START, IST), "to", datetime.fromtimestamp(END, IST),
      "requests", int(tot[keys[13]]), "errors", int(tot[keys[1]] + tot[keys[2]]))
for a, b, p in INC:   # use these with PromQL's @ to look at each incident hour (1 h window ending 50 min after it began)
    print("incident at", datetime.fromtimestamp(a, IST), " query it with @", a + 50 * 60)
