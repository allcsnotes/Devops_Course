"""traffic.py - simulated allcsvideos users (M16-L01, from M14-L04's generator).

  python traffic.py <base-url> <seconds> <rate> <out-name>
  - <rate> requests a second on a fixed schedule (open loop: users don't wait for slow answers),
    each in its own thread on a new connection, client timeout 2 s
  - 2 in 100 requests ask for /api/courses?sort=popular, the rest for /api/courses; user = one of 5,000 ids
  - every second it also reads the API's /metrics: db_pool_in_use and db_pool_waiting
  - prints one line per completed second:  HH:MM:SS req=n ok=n err=n p50=ms p99=ms pool=used/size wait=n
  - runs/<out>.csv       one line per request:  epoch_ms,route,status,latency_ms
  - runs/<out>-pool.csv  one line per second:   epoch_ms,in_use,waiting
"""
import http.client, random, sys, threading, time
from collections import defaultdict
from urllib.parse import urlparse

BASE, SECONDS, RATE, OUT = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
TIMEOUT = 2
u = urlparse(BASE)
lock = threading.Lock()
per_sec = defaultdict(lambda: defaultdict(int)); lat = defaultdict(list)
rows, pool_rows = [], []
pool_now = {}
pool_by_sec = {}
stop_at = time.time() + SECONDS
rnd = random.Random(16)


def get(path, timeout=TIMEOUT):
    c = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=timeout)
    c.request("GET", path); r = c.getresponse(); body = r.read(); c.close()
    return r.status, body


def one(path, route):
    t0 = time.time()
    try:
        status, _ = get(path); status = str(status)
    except TimeoutError:
        status = "timeout"
    except Exception:
        status = "conn"
    ms = int((time.time() - t0) * 1000)
    with lock:
        s = per_sec[int(t0)]; s["req"] += 1
        if status == "200": s["ok"] += 1
        else: s["err"] += 1
        lat[int(t0)].append(ms)
        rows.append(f"{int(t0 * 1000)},{route},{status},{ms}")


def schedule():
    nxt = time.time()
    while nxt < stop_at:
        time.sleep(max(0, nxt - time.time()))
        user = "u%04d" % rnd.randint(1, 5000)
        if rnd.random() < 0.02:
            args = (f"/api/courses?sort=popular&user={user}", "popular")
        else:
            args = (f"/api/courses?user={user}", "list")
        threading.Thread(target=one, args=args).start()
        nxt += 1 / RATE


def poll():
    while time.time() < stop_at + TIMEOUT:
        t = time.time()
        try:
            _, body = get("/metrics", 1)
            m = {}
            for ln in body.decode().splitlines():
                if ln.startswith(("db_pool_in_use ", "db_pool_waiting ", "db_pool_size ")):
                    k, v = ln.split(); m[k] = int(float(v))
            with lock:
                pool_now.update(m); pool_by_sec[int(t)] = dict(pool_now)
                pool_rows.append(f"{int(t * 1000)},{m.get('db_pool_in_use', '')},{m.get('db_pool_waiting', '')}")
        except Exception:
            with lock: pool_rows.append(f"{int(t * 1000)},,")
        time.sleep(max(0, 1 - (time.time() - t)))


def pct(v, p):
    if not v: return "-"
    v = sorted(v); return str(v[min(len(v) - 1, int(p * len(v)))])


def line(sec):
    s = per_sec.get(sec, {}); L = lat.get(sec, []); pn = pool_by_sec.get(sec, {})
    return (f"{time.strftime('%H:%M:%S', time.localtime(sec))} req={s.get('req', 0)} ok={s.get('ok', 0)} "
            f"err={s.get('err', 0)} p50={pct(L, .5)}ms p99={pct(L, .99)}ms "
            f"pool={pn.get('db_pool_in_use', '?')}/{pn.get('db_pool_size', '?')} wait={pn.get('db_pool_waiting', '?')}")


threading.Thread(target=poll, daemon=True).start()
sched = threading.Thread(target=schedule); sched.start()
last = int(time.time())
while sched.is_alive() or sum(1 for th in threading.enumerate() if not th.daemon) > 1:
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
    open(f"runs/{OUT}.csv", "w").write("\n".join(rows) + "\n")
    open(f"runs/{OUT}-pool.csv", "w").write("\n".join(pool_rows) + "\n")
    total = len(rows); bad = sum(1 for r in rows if r.split(",")[2] != "200")
print(f"done: {total} requests, {bad} failed", flush=True)
