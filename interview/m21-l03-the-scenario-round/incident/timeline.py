"""timeline.py RUN: build the incident timeline from real timestamps, and the response metrics.
Sources (all written during the run): runs/RUN.csv (every user request), runs/RUN-deploys.log (deploy.sh),
runs/RUN-pager.log (lab pager), runs/RUN-status.log (status page), runs/RUN-timeline.log (inc.sh notes)."""
import csv, json, os, sys, time

r = sys.argv[1]; D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "runs")
def jl(name):
    p = os.path.join(D, f"{r}-{name}.log")
    return [json.loads(l) for l in open(p)] if os.path.exists(p) else []
reqs = [(float(t), route, int(s)) for t, route, s, ms in csv.reader(open(os.path.join(D, f"{r}.csv")))]
bad = lambda s: s == 0 or s >= 500
deploys, pager, status, notes = jl("deploys"), jl("pager"), jl("status"), jl("timeline")
bad_deploy = next(d for d in deploys if d["version"] == "1.5.0")
fails = [q for q in reqs if bad(q[2]) and q[0] >= bad_deploy["epoch"] - 30]
t0, t_last = fails[0][0], fails[-1][0]
ev = [(n["epoch"], n["who"], n["msg"]) for n in notes]   # notes first: same second -> the person spoke first
ev += [(bad_deploy["epoch"], "deploy", f"catalog-api 1.5.0 rollout finished ({bad_deploy['by']})"),
      (t0, "users", "first failed request (impact starts)")]
for d in deploys:
    if d is not bad_deploy:
        if "start" in d: ev.append((d["start"], "deploy", f"rollback to {d['version']} started ({d['by']})"))
        ev.append((d["epoch"], "deploy", f"rollback to {d['version']} finished ({d['by']})"))
for p in pager:
    if p["epoch"] < bad_deploy.get("start", bad_deploy["epoch"]) - 60: continue   # left over from an earlier run
    if p["event"].startswith("ticket"):
        ev.append((p["epoch"], "ticket", f"{p['alert']} {p['event'].split()[1]} (ticket queue, nobody paged)")); continue
    who = f" {p['who']}" if p.get("who") else ""
    ev.append((p["epoch"], "pager", {"triggered": f"page #{p['page']} {p.get('alert')}", "notified": f"paged{who} ({p.get('role')})",
               "escalated": f"no ack in {p.get('after_s')} s: escalated to{who}", "acknowledged": f"acknowledged by{who}",
               "resolved": "alert resolved"}.get(p["event"], p["event"])))
for s in status:
    ev.append((s["epoch"], "status", f"{s['status']}: {s['component']} {s['state']}"))
if "start" in bad_deploy: ev.append((bad_deploy["start"], "deploy", f"catalog-api 1.5.0 rollout started ({bad_deploy['by']})"))
ev.append((t_last, "users", "last failed request (impact ends)"))
ev.sort(key=lambda e: e[0])
hm = lambda e: time.strftime("%H:%M:%S", time.localtime(e))
rel = lambda e: ("-" if e < t0 else "+") + "%02d:%02d" % divmod(int(round(abs(e - t0))), 60)
print(f"timeline of {r} (T = first failed request, {hm(t0)} local time)")
for e, src, msg in ev:
    print(f"{hm(e)}  T{rel(e)}  {src:<7} {msg}")
trig = next((p["epoch"] for p in pager if p["event"] == "triggered"), None)
ack = next((p["epoch"] for p in pager if p["event"] == "acknowledged"), None)
win = [q for q in reqs if t0 <= q[0] <= t_last]
nb = sum(1 for q in win if bad(q[2]))
mm = lambda s: "%d min %d s" % divmod(int(round(s)), 60)
print(f"time to detect (first failure -> page):       {mm(trig - t0)}")
if ack: print(f"time to acknowledge (page -> ack):            {mm(ack - trig)}")
print(f"time to restore (first -> last failure):      {mm(t_last - t0)}")
print(f"requests during impact: {len(win)}, failed: {nb} ({100 * nb / len(win):.1f}%)")
for route in ("/api/courses", "/api/courses/<id>"):
    w = [q for q in win if q[1] == route]; b = sum(1 for q in w if bad(q[2]))
    print(f"  {route:<18} {b} of {len(w)} failed ({100 * b / max(1, len(w)):.1f}%)")
budget = 10 * 86400 * 30 * 0.005
print(f"error budget used: {nb} of {budget:,.0f} failures allowed in 30 days at 10 req/s ({100 * nb / budget:.2f}%)")
