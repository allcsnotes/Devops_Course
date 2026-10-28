"""Simulated students for the M19-L04 lab: RATE requests a second until stopped (fake users, no real data).
Storefront (both bff replicas): 35% home, 30% course list, 20% one course page, 5% search. Copilot: 10% questions.
Every request goes to /runs/$RUN.csv (epoch,service,route,status,ms); every 10 s a one-line summary is printed."""
import os, random, signal, threading, time, urllib.error, urllib.parse, urllib.request

RATE, RUN = float(os.environ.get("RATE", "10")), os.environ.get("RUN", "run")
f = open(f"/runs/{RUN}.csv", "a", buffering=1)
lock, win = threading.Lock(), []
stop = threading.Event()
signal.signal(signal.SIGTERM, lambda *a: stop.set())
WORDS = ["python", "kubernetes", "docker", "graphs", "course", "system", "design", "java"]
USERS = ["lukas@example.com", "student042@example.com", "student117@example.com"]   # FAKE addresses


def pick():
    r, bff = random.random(), random.choice(["bff-1", "bff-2"])
    if r < 0.35: return "storefront-bff", "/", f"http://{bff}:8080/"
    if r < 0.65: return "storefront-bff", "/courses", f"http://{bff}:8080/courses"
    if r < 0.85: return "storefront-bff", "/course/<id>", f"http://{bff}:8080/course/{random.randint(101, 124)}"
    if r < 0.90: return "storefront-bff", "/search", f"http://{bff}:8080/search?q=" + random.choice(WORDS)
    q = urllib.parse.urlencode({"q": "which course teaches " + random.choice(WORDS), "user": random.choice(USERS)})
    return "course-copilot", "/ask", "http://copilot:8080/ask?" + q


def one():
    svc, route, url = pick()
    t0, start = time.perf_counter(), time.time()
    try:
        with urllib.request.urlopen(url, timeout=4) as r:
            r.read(); code = r.status
    except urllib.error.HTTPError as e:
        code = e.code
    except Exception:
        code = 0                      # timeout or connection refused
    ms = (time.perf_counter() - t0) * 1000
    with lock:
        f.write(f"{start:.3f},{svc},{route},{code},{ms:.1f}\n")
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
time.sleep(4.5)
f.close()
