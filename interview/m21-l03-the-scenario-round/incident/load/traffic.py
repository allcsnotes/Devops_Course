"""Simulated students for the M17-L02 lab: RATE requests a second until stopped (fake users, no real data).
7 in 10 open the course list (/api/courses), 3 in 10 open one course page. 3 second client timeout.
Every request goes to /runs/$RUN.csv (epoch,route,status,ms); every 10 s a one-line summary is printed."""
import os, random, signal, sys, threading, time, urllib.error, urllib.request

RATE, RUN = float(os.environ.get("RATE", "10")), os.environ.get("RUN", "run")
BASE = os.environ.get("URL", "http://api:8080")
f = open(f"/runs/{RUN}.csv", "a", buffering=1)
lock, win = threading.Lock(), []
stop = threading.Event()
signal.signal(signal.SIGTERM, lambda *a: stop.set())


def one():
    route = "/api/courses" if random.random() < 0.7 else "/api/courses/<id>"
    url = BASE + ("/api/courses" if route == "/api/courses" else f"/api/courses/{random.randint(101, 124)}")
    t0, start = time.perf_counter(), time.time()
    try:
        with urllib.request.urlopen(url, timeout=3) as r:
            r.read(); code = r.status
    except urllib.error.HTTPError as e:
        code = e.code
    except Exception:
        code = 0                      # timeout or connection refused
    ms = (time.perf_counter() - t0) * 1000
    with lock:
        f.write(f"{start:.3f},{route},{code},{ms:.1f}\n")
        win.append((code, ms))


def report():
    while not stop.wait(10):
        with lock:
            w = win[:]; win.clear()
        bad = sum(1 for c, _ in w if c == 0 or c >= 500)
        print(f"{time.strftime('%H:%M:%S')} last 10s: {len(w)} requests, {bad} failed ({100 * bad / max(1, len(w)):.0f}%)", flush=True)


threading.Thread(target=report, daemon=True).start()
t, i = time.perf_counter(), 0
while not stop.is_set():
    time.sleep(max(0, t + i / RATE - time.perf_counter()))
    threading.Thread(target=one, daemon=True).start()
    i += 1
time.sleep(3.5)
f.close()
