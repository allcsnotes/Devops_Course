#!/usr/bin/env python3
"""dr/report.py <drill name>: the real RTO and RPO of a drill, from timestamps only.
  /srv/drill/events.log    the shared drill log (DISASTER, each runbook step, restore complete)
  ~/students/acks.csv      every enrollment the site confirmed to a student (time, id, student)
  ~/students/requests.csv  every request the students sent (time, route, result)
  the restored database    which of the confirmed enrollments survived
RPO = the disaster minus the newest confirmed enrollment that survived; lost = confirmed enrollments that are gone.
RTO = the disaster until students can enroll again (first confirmed enrollment after it), and until verify passed."""
import os, subprocess, sys
from datetime import datetime
H = os.path.expanduser("~"); name = sys.argv[1] if len(sys.argv) > 1 else "drill"
ts = lambda s: datetime.strptime(s[:23], "%Y-%m-%d %H:%M:%S.%f")
ev = []
for line in open("/srv/drill/events.log"):
    ev.append((ts(line), line[24:].strip()))
t0 = max(t for t, e in ev if e.startswith("DISASTER"))
ev = [(t, e) for t, e in ev if t >= t0]
done = next((t for t, e in ev if e == "restore complete"), None)
acks = [l.strip().split(",") for l in open(f"{H}/students/acks.csv") if l.strip()]
before = [(ts(a[0]), int(a[1]), a[2]) for a in acks if ts(a[0]) < t0]
after = [ts(a[0]) for a in acks if ts(a[0]) > t0]
lo = min(i for _, i, _ in before[-5000:])
rows = subprocess.run(["psql", "-h", "10.0.202.10", "-U", "postgres", "-d", "catalog", "-At", "-F", ",", "-c",
                       f"select id, student from enrollments where id >= {lo}"], capture_output=True, text=True).stdout
have = {tuple(r.split(",")) for r in rows.split()}
kept = [a for a in before[-5000:] if (str(a[1]), a[2]) in have]
newest = max(a[0] for a in kept) if kept else before[-5000:][0][0]
# lost = confirmed after the newest surviving one (older gaps belong to an earlier drill)
lost = [a for a in before[-5000:] if a[0] > newest and (str(a[1]), a[2]) not in have]
fmt = lambda t: t.strftime("%H:%M:%S")
mm = lambda s: f"{int(s // 60)} min {int(s % 60):02d} s"
print(f"== {name}")
print(f"disaster (staged)              {fmt(t0)}")
for t, e in ev[1:]:
    if e != "restore complete":
        print(f"  +{mm((t - t0).total_seconds()):>13}  {e.split(':')[0]}")
print(f"newest confirmed row restored  {fmt(newest)}")
print(f"RPO (data lost)                {mm((t0 - newest).total_seconds())}, {len(lost)} confirmed enrollments gone")
if after:
    print(f"students enroll again          {fmt(min(after))}  RTO {mm((min(after) - t0).total_seconds())}")
if done:
    print(f"verify passed, clock stopped   {fmt(done)}  RTO {mm((done - t0).total_seconds())}")
