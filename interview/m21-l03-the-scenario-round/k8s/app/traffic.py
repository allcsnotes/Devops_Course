# traffic.py: open-model load against http://catalog.allcs (like users: arrivals don't wait for answers).
# RATE requests per second, each with a 2 s timeout. Prints one line per 5 s: sent, ok, failed, p95 latency.
import os, threading, time, urllib.request
URL = os.environ.get("URL", "http://catalog.allcs/courses"); RATE = float(os.environ.get("RATE", "20"))
DUR = int(os.environ.get("DURATION", "0")); lock = threading.Lock(); win = []
def one():
    t = time.time(); ok = False
    try:
        with urllib.request.urlopen(URL, timeout=2) as r: ok = r.status == 200; r.read()
    except Exception: pass
    with lock: win.append((ok, time.time() - t))
def report():
    while True:
        time.sleep(5)
        with lock: w = win[:]; win.clear()
        if not w: continue
        lat = sorted(d for o, d in w if o); p95 = lat[int(len(lat) * .95) - 1] * 1000 if lat else 0
        print(f"{time.strftime('%H:%M:%S')} sent={len(w)} ok={sum(o for o, d in w)} failed={sum(not o for o, d in w)} p95={p95:.0f}ms", flush=True)
threading.Thread(target=report, daemon=True).start()
print(f"{time.strftime('%H:%M:%S')} traffic: {RATE:g} req/s to {URL}", flush=True)
t0 = time.time(); i = 0
while not DUR or time.time() - t0 < DUR:
    i += 1; nxt = t0 + i / RATE; time.sleep(max(0, nxt - time.time()))
    threading.Thread(target=one, daemon=True).start()
time.sleep(6)
