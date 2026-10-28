"""traffic.py - simulated users for M09-L02. Hits the load balancer at a steady rate and records what came back.

  python traffic.py <url> <seconds> <out-prefix>
  - RATE requests a second on a fixed schedule, each in its own thread with a new connection (like separate users:
    a slow or hanging request never delays the next one)
  - 70% ask a question (/ask?q=...), 30% read /version
  - every response is sorted by the X-App-Version header and the status code; failures with no response
    (connection refused, timeout after 2 s) count as "conn"
  - <out>.csv   one line per request:  epoch_ms,path,status,version,latency_ms
  - <out>.jsonl one line per second:   {"t": epoch_s, "1.6.0": n, "1.7.0": n, ..., "s200": n, "s500": n, "s502": n, "conn": n}
"""
import http.client, json, random, sys, threading, time
from collections import defaultdict
from urllib.parse import urlparse

URL, SECONDS, OUT = sys.argv[1], float(sys.argv[2]), sys.argv[3]
RATE = 40
u = urlparse(URL)
QUESTIONS = ["docker", "kubernetes basics", "graphs", "caching", "spring jpa", "rag", "linux"]
lock = threading.Lock()
per_sec = defaultdict(lambda: defaultdict(int))
rows = []
stop_at = time.time() + SECONDS


def one():
    path = f"/ask?q={random.choice(QUESTIONS).replace(' ', '+')}" if random.random() < 0.7 else "/version"
    t0 = time.time()
    try:
        c = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=2)
        c.request("GET", path)
        r = c.getresponse(); r.read()
        status, ver = str(r.status), r.getheader("X-App-Version", "-")
        c.close()
    except Exception:
        status, ver = "conn", "-"
    with lock:
        s = per_sec[int(t0)]
        s["s" + status if status != "conn" else "conn"] += 1
        if ver != "-": s[ver] += 1
        rows.append(f"{int(t0*1000)},{path.split('?')[0]},{status},{ver},{int((time.time()-t0)*1000)}")


def schedule():
    nxt = time.time()
    while nxt < stop_at:
        time.sleep(max(0, nxt - time.time()))
        threading.Thread(target=one).start()
        nxt += 1 / RATE


sched = threading.Thread(target=schedule); sched.start()
last = int(time.time())
while sched.is_alive() or threading.active_count() > 1:
    time.sleep(0.25)
    now = int(time.time())
    with lock:
        for sec in range(last, now - 2):   # print seconds that are complete
            s = per_sec.get(sec, {})
            print(time.strftime("%H:%M:%S", time.localtime(sec)), " ".join(f"{k}={v}" for k, v in sorted(s.items())), flush=True)
        last = max(last, now - 2)
with open(OUT + ".jsonl", "w") as f:
    for sec in sorted(per_sec):
        f.write(json.dumps({"t": sec, **per_sec[sec]}) + "\n")
with open(OUT + ".csv", "w") as f:
    f.write("epoch_ms,path,status,version,latency_ms\n" + "\n".join(sorted(rows)) + "\n")
print("done", len(rows), "requests")
