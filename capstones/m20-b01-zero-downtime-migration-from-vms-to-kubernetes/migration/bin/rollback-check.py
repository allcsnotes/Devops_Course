#!/usr/bin/env python3
"""rollback-check.py RUN: how fast did a rollback to 0 % take effect? Reads the last "0" event in k6/out/events.log
(written by shift.sh) and the requests in k6/out/RUN.log: the last request Kubernetes answered after it, and the
failed requests in the 10 s around it."""
import re, sys, os, datetime
run = sys.argv[1]; O = os.path.expanduser("~/migration/k6/out")
ev = [l.split() for l in open(f"{O}/events.log")]
rows = []
for line in open(f"{O}/{run}.log"):
    m = re.search(r'msg="(\d+) (\S+) (\d+) ([\d.]+) (\S+) (\S+)"', line)
    if m: rows.append((int(m[1]), m[2], int(m[3]), float(m[4]), m[5]))
t0, t1 = rows[0][0], rows[-1][0]
back = [int(e[0]) for e in ev if e[1] == "0" and t0 <= int(e[0]) <= t1][-1]
k8s_after = [r for r in rows if r[1] == "k8s" and r[0] - r[3] >= back - 1]
last = max((r[0] for r in rows if r[1] == "k8s"), default=None)
fmt = lambda ms: datetime.datetime.fromtimestamp(ms / 1000).strftime("%H:%M:%S.%f")[:-3]
bad = [r for r in rows if abs(r[0] - back) <= 10000 and r[2] != (201 if r[4] == "progress" else 200)]
print(f"rollback to 0 %:                  {fmt(back)}")
print(f"last answer from Kubernetes:      {fmt(last)} ({last - back:+d} ms)")
print(f"requests sent to Kubernetes after: {len([r for r in rows if r[1] == 'k8s' and r[0] - r[3] > back + 50])}")
print(f"failed requests within 10 s:      {len(bad)}")
