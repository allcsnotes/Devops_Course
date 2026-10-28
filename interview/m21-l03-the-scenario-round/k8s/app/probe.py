# probe.py PATH N: time N GETs (one per second) to the catalog Service, like the kubelet's probe (but a 10 s timeout)
import sys, time, urllib.request
url = "http://catalog.allcs" + (sys.argv[1] if len(sys.argv) > 1 else "/healthz")
for i in range(int(sys.argv[2]) if len(sys.argv) > 2 else 1):
    t = time.time()
    try:
        with urllib.request.urlopen(url, timeout=10) as r: print(f"{time.strftime('%H:%M:%S')} {url} -> {r.status} in {time.time() - t:.3f} s", flush=True)
    except Exception as e: print(f"{time.strftime('%H:%M:%S')} {url} -> {type(e).__name__} after {time.time() - t:.3f} s", flush=True)
    time.sleep(max(0, 1 - (time.time() - t)))
