"""Simulated students for the M16-L05 lab: N page loads at a fixed rate, random users, then a one-line summary.
Uses only the standard library; it sends no trace headers, so every page load starts a new trace at storefront-bff."""
import os, random, sys, threading, time, urllib.error, urllib.request
N, RATE = int(os.environ.get("N", "300")), float(os.environ.get("RATE", "10"))
URL = os.environ.get("URL", "http://bff:8080/catalog")
res, lock = [], threading.Lock()
def one():
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(f"{URL}?user=u{random.randint(1, 200000)}", timeout=10) as r:
            code = r.status
    except urllib.error.HTTPError as e:
        code = e.code
    except Exception:
        code = 0
    with lock:
        res.append((code, time.perf_counter() - t0))
start = time.perf_counter(); ts = []
for i in range(N):
    time.sleep(max(0, start + i / RATE - time.perf_counter()))
    t = threading.Thread(target=one); t.start(); ts.append(t)
for t in ts:
    t.join()
ok = sum(1 for c, _ in res if c == 200)
d = sorted(x for _, x in res)
print(f"sent={N} ok={ok} failed={N - ok} p50={d[len(d)//2]*1000:.0f}ms p95={d[int(len(d)*.95)]*1000:.0f}ms")
