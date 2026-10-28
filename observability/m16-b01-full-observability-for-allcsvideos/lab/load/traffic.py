"""Simulated students for the M16-B01 lab: course list and Course Copilot questions at fixed rates, through the API.
Prints one line per second: HH:MM:SS courses ok/err  ask ok/err  p99 of ask. Standard library only."""
import os, random, threading, time, urllib.error, urllib.parse, urllib.request
API = os.environ.get("API", "http://api:8080")
RC, RA = float(os.environ.get("RATE_COURSES", "6")), float(os.environ.get("RATE_ASK", "2"))
QS = ["how do I learn docker", "teach me kubernetes", "what about prometheus", "graphs please", "spring", "rag",
      "where is terraform", "caching", "linux basics", "grafana dashboards"]
lock = threading.Lock(); sec = {}
def one(kind, t_sched):
    url = f"{API}/api/courses" if kind == "c" else f"{API}/api/ask?" + urllib.parse.urlencode({"q": random.choice(QS)})
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            ok = r.status == 200; r.read()
    except Exception:
        ok = False
    d = time.perf_counter() - t0
    with lock:
        s = sec.setdefault(int(t_sched), {"c": [0, 0], "a": [0, 0], "lat": []})
        s[kind][0 if ok else 1] += 1
        if kind == "a": s["lat"].append(d)
def sched(kind, rate):
    t = time.time()
    while True:
        t += random.expovariate(rate)
        time.sleep(max(0, t - time.time()))
        threading.Thread(target=one, args=(kind, t), daemon=True).start()
for k, r in (("c", RC), ("a", RA)):
    threading.Thread(target=sched, args=(k, r), daemon=True).start()
while True:
    time.sleep(1)
    cut = int(time.time()) - 6        # print a second once its slowest request (5 s timeout) is done
    with lock:
        for k in sorted(x for x in sec if x <= cut):
            s = sec.pop(k); L = sorted(s["lat"]); p99 = L[min(len(L) - 1, int(len(L) * .99))] * 1000 if L else 0
            print(time.strftime("%H:%M:%S", time.localtime(k)), f"courses ok={s['c'][0]} err={s['c'][1]}",
                  f"ask ok={s['a'][0]} err={s['a'][1]} max_ms={p99:.0f}", flush=True)
