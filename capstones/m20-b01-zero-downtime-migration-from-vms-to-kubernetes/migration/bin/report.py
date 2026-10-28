#!/usr/bin/env python3
"""report.py RUN: what the students saw in one run, from k6/out/RUN.log (one line per request, written by k6).
Per pool: requests, failed requests, p95 and p99 latency. Plus the progress writes the API acknowledged (201)."""
import re, sys, os
run = sys.argv[1]
rows = []
for line in open(os.path.expanduser(f"~/migration/k6/out/{run}.log")):
    m = re.search(r'msg="(\d+) (\S+) (\d+) ([\d.]+) (\S+) (\S+)"', line)
    if m:
        rows.append((int(m[1]), m[2], int(m[3]), float(m[4]), m[5]))
ok = lambda r: r[2] == (201 if r[4] == "progress" else 200)
def pct(v, p):
    v = sorted(v); return v[min(len(v) - 1, int(len(v) * p))] if v else 0
t = (rows[-1][0] - rows[0][0]) / 1000
print(f"run {run}: {len(rows):,} requests in {int(t // 60)}m {int(t % 60):02d}s ({len(rows) / t:.1f} per second)")
print(f"{'pool':<6} {'requests':>9} {'failed':>7} {'p95 ms':>8} {'p99 ms':>8}")
for name in ["vm", "k8s", "none", "all"]:
    rs = [r for r in rows if name == "all" or r[1] == name]
    if not rs: continue
    d = [r[3] for r in rs]
    print(f"{name:<6} {len(rs):>9,} {sum(not ok(r) for r in rs):>7} {pct(d, .95):>8.1f} {pct(d, .99):>8.1f}")
print(f"progress writes acknowledged (201): {sum(1 for r in rows if r[4] == 'progress' and r[2] == 201):,}")
bad = [r for r in rows if not ok(r)]
if bad:
    from collections import Counter
    print("failed requests by pool, status and route:")
    for (p, s, rt), n in sorted(Counter((r[1], r[2], r[4]) for r in bad).items(), key=lambda x: -x[1]):
        print(f"  {p:<4} {s}  {rt:<9} {n:>5}")
