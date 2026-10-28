"""timeline.py SCENARIO [N]: the timeline of one game-day scenario, and its numbers, from real timestamps only.
Sources, all written during the run: runs/students.csv (every simulated request), incident/gm-events.log (game master),
incident/deploys.log (deploy.sh), incident/flags.log (flag.sh), incident/pager.log (lab pager), incident/status.log
(status page), incident/timeline.log (inc.sh notes). N picks the Nth run of the same scenario (default: the last)."""
import csv, json, os, sys, time

D = os.path.dirname(os.path.abspath(__file__))
sc, nth = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else -1
def jl(name):
    p = os.path.join(D, "incident", name)
    return [json.loads(l) for l in open(p) if l.strip()] if os.path.exists(p) else []
gm = [e for e in jl("gm-events.log") if e["scenario"] == sc]
inj = [e for e in gm if e["event"] == "inject"][nth]["epoch"]
end = next(e["epoch"] for e in gm if e["event"] == "rollback" and e["epoch"] >= inj)
nxt = min([e["epoch"] for e in jl("gm-events.log") if e["event"] == "inject" and e["epoch"] > inj] + [end + 600])
lo, hi = inj - 5, min(end + 300, nxt - 1)                    # the window this scenario owns (5 min after)
BUDGET = {"catalog-availability": 46656, "catalog-latency": 466560, "copilot-availability": 51840}
reqs = [(float(t), r, c, float(ms)) for t, r, c, ms in csv.reader(open(os.path.join(D, "runs", "students.csv"))) if lo <= float(t) <= hi]
bad = {"catalog-availability": [q for q in reqs if q[1] == "/api/courses" and (q[2] == "error" or q[2][0] == "5")],
       "catalog-latency": [q for q in reqs if q[1] == "/api/courses" and q[3] > 250],
       "copilot-availability": [q for q in reqs if q[1] == "/api/ask" and (q[2] == "error" or q[2][0] == "5")]}
ev = [(inj, "gm", "fault injected (sealed scenario " + sc + ")"), (end, "gm", "fault removed")]
for k, L in bad.items():
    if L: ev += [(L[0][0], "users", f"first {k} bad request"), (L[-1][0], "users", f"last {k} bad request")]
inwin = lambda e: lo <= e["epoch"] <= hi
for d in filter(inwin, jl("deploys.log")): ev.append((d["epoch"], "deploy", f"catalog-api {d['version']} rolled out ({d['by']})"))
for f in filter(inwin, jl("flags.log")): ev.append((f["epoch"], "flag", f"{f['flag']} = {f['value']}"))
pages = {}
for p in filter(inwin, jl("pager.log")):
    if p["event"].startswith("ticket"):
        ev.append((p["epoch"], "ticket", f"{p['alert']} {p['event'].split()[1]} (ticket queue)")); continue
    if p["event"] == "triggered": pages[p["page"]] = p.get("summary", "").split(":")[0]
    who = f" {p['who']}" if p.get("who") else ""
    msg = {"triggered": f"page #{p['page']} {p.get('summary', '')[:58]}", "notified": f"page #{p['page']}: notified{who}",
           "escalated": f"page #{p['page']}: escalated to{who}", "acknowledged": f"page #{p['page']}: acknowledged by{who}",
           "resolved": f"page #{p['page']} ({pages.get(p['page'], '?')}): resolved"}.get(p["event"], p["event"])
    if p["event"] != "notified": ev.append((p["epoch"], "pager", msg))
for s in filter(inwin, jl("status.log")): ev.append((s["epoch"], "status", f"{s['status']}: {s['component']} {s['state']}"))
for n in filter(inwin, jl("timeline.log")): ev.append((n["epoch"], n["who"], n["msg"]))
ev.sort(key=lambda e: e[0])
hm = lambda e: time.strftime("%H:%M:%S", time.localtime(e))
rel = lambda e: ("-" if e < inj else "+") + "%02d:%02d" % divmod(int(round(abs(e - inj))), 60)
print(f"timeline of scenario {sc} (T = fault injected, {hm(inj)} IST)")
for e, src, msg in ev:
    print(f"{hm(e)}  T{rel(e)}  {src:<7} {msg[:74]}")
mm = lambda s: "%d min %02d s" % divmod(int(round(s)), 60)
first = lambda name: next((p["epoch"] for p in filter(inwin, jl("pager.log")) if p["event"] == name and p["epoch"] >= inj), None)
trig = first("triggered"); ack = first("acknowledged"); tick = first("ticket firing")
mit = next((n["epoch"] for n in filter(inwin, jl("timeline.log")) if "mitigated" in n["msg"].lower()), None)
if trig: print(f"time to detect (fault -> first page):    {mm(trig - inj)}")
if tick: print(f"time to ticket (fault -> first ticket):  {mm(tick - inj)}")
if ack and trig: print(f"time to acknowledge (page -> ack):       {mm(ack - trig)}")
if mit: print(f"time to mitigate (fault -> 'mitigated'): {mm(mit - inj)}")
for k, L in bad.items():
    route = "/api/ask" if k.startswith("copilot") else "/api/courses"
    n = sum(1 for q in reqs if q[1] == route and q[0] >= inj)
    span = f", for {mm(L[-1][0] - L[0][0])}" if L else ""
    print(f"{k:<21} {len(L):>5} bad of {n:>5}{span}: {100 * len(L) / BUDGET[k]:.2f}% of the 30-day budget")
