"""traffic.py - simulated launch-day users inside the cluster (M14-L04, from M14-L03 and M13-L04's generator).

  python traffic.py <url> <seconds> <rate> <out-prefix>
  - <rate> requests a second on a fixed schedule (open loop: users don't wait for slow answers),
    each in its own thread on a new connection, timeout 2 s
  - prints one line per completed second:  HH:MM:SS ok=n timeout=n err=n p50=ms p95=ms pods=n
  - <out>.csv: one line per request: epoch_ms,status,pod,latency_ms
"""
import http.client, sys, threading, time
from collections import defaultdict
from urllib.parse import urlparse

URL, SECONDS, RATE, OUT = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
TIMEOUT = 2
u = urlparse(URL)
path = u.path + ("?" + u.query if u.query else "")
lock = threading.Lock()
per_sec = defaultdict(lambda: defaultdict(int))
lat = defaultdict(list)
pods = defaultdict(set)
rows = []
stop_at = time.time() + SECONDS


def one():
    t0 = time.time()
    try:
        c = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=TIMEOUT)
        c.request("GET", path)
        r = c.getresponse(); r.read()
        status, pod = str(r.status), r.getheader("X-Pod", "-")
        c.close()
    except TimeoutError:
        status, pod = "timeout", "-"
    except Exception:
        status, pod = "conn", "-"
    ms = int((time.time() - t0) * 1000)
    with lock:
        s = per_sec[int(t0)]
        if status == "200":
            s["ok"] += 1; lat[int(t0)].append(ms); pods[int(t0)].add(pod)
        else:
            s["timeout" if status == "timeout" else "err"] += 1
        rows.append(f"{int(t0 * 1000)},{status},{pod},{ms}")


def schedule():
    nxt = time.time()
    while nxt < stop_at:
        time.sleep(max(0, nxt - time.time()))
        threading.Thread(target=one).start()
        nxt += 1 / RATE


def pct(v, p):
    if not v: return "-"
    v = sorted(v); return str(v[min(len(v) - 1, int(p * len(v)))])


def line(sec):
    s = per_sec.get(sec, {}); L = lat.get(sec, [])
    return (f"{time.strftime('%H:%M:%S', time.localtime(sec))} ok={s.get('ok', 0)} timeout={s.get('timeout', 0)} "
            f"err={s.get('err', 0)} p50={pct(L, .5)}ms p95={pct(L, .95)}ms pods={len(pods.get(sec, ()))}")


sched = threading.Thread(target=schedule); sched.start()
last = int(time.time())
while sched.is_alive() or threading.active_count() > 1:
    time.sleep(0.25)
    now = int(time.time())
    with lock:
        for sec in range(last, now - TIMEOUT - 1):   # seconds whose requests have all finished
            print(line(sec), flush=True)
        last = max(last, now - TIMEOUT - 1)
with lock:
    for sec in range(last, int(time.time()) + 1):
        if sec in per_sec: print(line(sec), flush=True)
    rows.sort()
    open(OUT + ".csv", "w").write("\n".join(rows) + "\n")
    total = len(rows); bad = sum(1 for r in rows if r.split(",")[1] != "200")
print(f"done: {total} requests, {bad} failed", flush=True)
