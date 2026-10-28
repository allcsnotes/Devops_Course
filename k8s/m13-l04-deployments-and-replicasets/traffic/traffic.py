"""traffic.py - simulated users inside the cluster (M13-L04, after M09-L02's generator).

  python traffic.py <url> <seconds> <out-prefix>
  - RATE (20) requests a second on a fixed schedule, each in its own thread on a new connection, timeout 2 s
  - every answer is sorted by status and by the X-App-Version header; X-Pod says which pod answered;
    no answer at all (connection refused, reset, timeout) counts as "conn"
  - prints one line per completed second:  HH:MM:SS 1.0.0=n 2.0.0=n ... err=n pods=n
  - <out>.csv: one line per request: epoch_ms,status,version,pod,latency_ms
"""
import http.client, sys, threading, time
from collections import defaultdict
from urllib.parse import urlparse

URL, SECONDS, OUT = sys.argv[1], float(sys.argv[2]), sys.argv[3]
RATE = 20
u = urlparse(URL)
lock = threading.Lock()
per_sec = defaultdict(lambda: defaultdict(int))
pods = defaultdict(set)
rows = []
stop_at = time.time() + SECONDS


def one():
    t0 = time.time()
    try:
        c = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=2)
        c.request("GET", u.path or "/")
        r = c.getresponse(); r.read()
        status, ver, pod = str(r.status), r.getheader("X-App-Version", "-"), r.getheader("X-Pod", "-")
        c.close()
    except Exception:
        status, ver, pod = "conn", "-", "-"
    with lock:
        s = per_sec[int(t0)]
        if status == "200":
            s[ver] += 1
            pods[int(t0)].add(pod)
        else:
            s["err"] += 1
        rows.append(f"{int(t0 * 1000)},{status},{ver},{pod},{int((time.time() - t0) * 1000)}")


def schedule():
    nxt = time.time()
    while nxt < stop_at:
        time.sleep(max(0, nxt - time.time()))
        threading.Thread(target=one).start()
        nxt += 1 / RATE


def line(sec):
    s = per_sec.get(sec, {})
    vs = " ".join(f"{k}={v}" for k, v in sorted(s.items()) if k != "err")
    return f"{time.strftime('%H:%M:%S', time.localtime(sec))} {vs} err={s.get('err', 0)} pods={len(pods.get(sec, ()))}"


sched = threading.Thread(target=schedule); sched.start()
first = last = int(time.time())
while sched.is_alive() or threading.active_count() > 1:
    time.sleep(0.25)
    now = int(time.time())
    with lock:
        for sec in range(last, now - 2):   # seconds whose requests have all finished (timeout 2 s)
            print(line(sec), flush=True)
        last = max(last, now - 2)
with lock:
    for sec in range(last, int(time.time()) + 1):
        if sec in per_sec: print(line(sec), flush=True)
    rows.sort()
    open(OUT + ".csv", "w").write("\n".join(rows) + "\n")
    total = len(rows); bad = sum(1 for r in rows if r.split(",")[1] != "200")
print(f"done: {total} requests, {bad} failed", flush=True)
