"""Simulated allcsvideos students for the M16-L06 lab (from M16-L01's generator), running until stopped.
RATE requests a second on a fixed schedule, each in its own thread, client timeout 2 s.
2 in 100 ask for /api/courses?sort=popular (slow on purpose), the rest for /api/courses.
Every 10 s it prints: HH:MM:SS req=n ok=n err=n"""
import http.client, os, random, threading, time
RATE = float(os.environ.get("RATE", "10")); HOST = os.environ.get("API", "api")
lock = threading.Lock(); c = {"req": 0, "ok": 0, "err": 0}; rnd = random.Random(16)

def one(path):
    ok = False
    try:
        h = http.client.HTTPConnection(HOST, 8080, timeout=2)
        h.request("GET", path); r = h.getresponse(); r.read(); h.close(); ok = r.status == 200
    except Exception:
        pass
    with lock:
        c["req"] += 1; c["ok" if ok else "err"] += 1

start = time.time(); i = 0; last = start
while True:
    time.sleep(max(0, start + i / RATE - time.time())); i += 1
    path = "/api/courses?sort=popular" if rnd.random() < .02 else "/api/courses"
    threading.Thread(target=one, args=(f"{path}{'&' if '?' in path else '?'}user=u{rnd.randint(1, 5000)}",), daemon=True).start()
    if time.time() - last >= 10:
        last += 10
        with lock:
            print(time.strftime("%H:%M:%S"), f"req={c['req']} ok={c['ok']} err={c['err']}", flush=True); c.update(req=0, ok=0, err=0)
