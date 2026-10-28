"""Traffic generator for the M09-L03 lab: steady, open-loop load on Course Copilot through the load balancer.

usage: python traffic.py <name> <seconds> [rps]
Every tick it sends one request, alternating /ask and /lessons/7/notes, for a random user out of 1000:
  u0001-u0005 role staff (the team) · u0006-u0025 role beta (the beta testers) · u0026-u1000 role student.
Writes one CSV row per request to /out/<name>.csv and prints one summary line per second.
"""
import csv
import random
import sys
import threading
import time
import urllib.error
import urllib.request

BASE = "http://lb"
name, secs = sys.argv[1], float(sys.argv[2])
rps = float(sys.argv[3]) if len(sys.argv) > 3 else 20
random.seed(9)
rows, lock = [], threading.Lock()


def role(n):
    return "staff" if n <= 5 else "beta" if n <= 25 else "student"


def one(i, t0):
    n = random.randint(1, 1000)
    user = f"u{n:04d}"
    kind = "ask" if i % 2 == 0 else "notes"
    url = (f"{BASE}/ask?q=docker&user={user}" if kind == "ask"
           else f"{BASE}/lessons/7/notes?user={user}&role={role(n)}")
    s = time.time()
    status, result, host = 0, "error", ""
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            import json
            body = json.load(r)
            status = r.status
            result = body.get("source") or body.get("notes")
            host = body.get("host", "")
    except urllib.error.HTTPError as e:
        status = e.code
    except Exception:
        status = 0
    ms = (time.time() - s) * 1000
    with lock:
        rows.append([round(s - t0, 3), time.strftime("%H:%M:%S", time.localtime(s)), kind, user, role(n),
                     status, round(ms, 1), result, host])


t0 = time.time()
threads, i, last = [], 0, 0
while time.time() - t0 < secs:
    th = threading.Thread(target=one, args=(i, t0))
    th.start()
    threads.append(th)
    i += 1
    nxt = t0 + i / rps
    time.sleep(max(0, nxt - time.time()))
    sec = int(time.time() - t0)
    if sec > last:
        with lock:
            cur = [r for r in rows if last - 1 <= r[0] < last]
        ask = [r for r in cur if r[2] == "ask"]
        err = sum(1 for r in ask if r[5] != 200)
        v2 = sum(1 for r in cur if r[7] == "v2")
        nt = sum(1 for r in cur if r[2] == "notes")
        print(f"{time.strftime('%H:%M:%S')}  ask {len(ask):2d}  errors {err:2d}  notes v2 {v2:2d}/{nt:2d}", flush=True)
        last = sec
for th in threads:
    th.join()
rows.sort()
with open(f"/out/{name}.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["t", "clock", "kind", "user", "role", "status", "ms", "result", "host"])
    w.writerows(rows)
print(f"{len(rows)} requests -> {name}.csv", flush=True)
