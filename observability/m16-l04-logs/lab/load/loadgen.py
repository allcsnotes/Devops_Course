"""Simulated allcsvideos students for M16-L04: REQUESTS requests through the web gateway, WORKERS keep-alive connections.
Mix: course list 55 %, one course 30 %, checkout 12 % (some with coupons), login 3 %. Fake users only (example.com).
At request STAGED_AT, the student Lukas checks out with coupon LAUNCH2026 (the staged bug); his reference is saved to
/runs/staged.json. Progress every 10 s on stdout."""
import http.client, json, os, random, threading, time

N = int(os.environ.get("REQUESTS", "1000"))
WORKERS = int(os.environ.get("WORKERS", "8"))
STAGED_AT = int(os.environ.get("STAGED_AT", "-1"))
HOST = os.environ.get("TARGET", "web")
lock = threading.Lock()
nxt = 0; done = 0; bad = 0; t0 = time.time()


def one(conn, i, rnd):
    user = f"u{rnd.randint(1000, 9999)}"
    hdr = {"X-User": user, "Content-Type": "application/json"}
    if i == STAGED_AT:
        user = "u4711"; hdr["X-User"] = user
        body = {"course_id": 103, "coupon": "LAUNCH2026", "email": "lukas@example.com"}
        conn.request("POST", "/api/checkout", json.dumps(body), hdr)
    else:
        r = rnd.random()
        if r < .55:
            conn.request("GET", "/api/courses", headers=hdr)
        elif r < .85:
            conn.request("GET", f"/api/courses/{rnd.choice([101, 102, 103, 104, 105, 106, 107])}", headers=hdr)
        elif r < .97:
            body = {"course_id": rnd.randint(101, 106), "coupon": rnd.choice([None, None, None, "WELCOME10", "DIWALI25"]),
                    "email": f"{user}@example.com"}
            conn.request("POST", "/api/checkout", json.dumps(body), hdr)
        else:
            conn.request("POST", "/api/login", json.dumps({"email": f"{user}@example.com", "password": "demo-password-123"}), hdr)
    resp = conn.getresponse(); data = resp.read()
    if i == STAGED_AT:
        rec = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "status": resp.status,
               "x_request_id": resp.getheader("X-Request-ID"), "body": json.loads(data)}
        json.dump(rec, open("/runs/staged.json", "w"), indent=1); print("STAGED", json.dumps(rec), flush=True)
    return resp.status


def worker(k):
    global nxt, done, bad
    rnd = random.Random(k); conn = http.client.HTTPConnection(HOST, 8080, timeout=10)
    while True:
        with lock:
            if nxt >= N: return
            i = nxt; nxt += 1
        try:
            s = one(conn, i, rnd)
        except Exception:
            conn.close(); conn = http.client.HTTPConnection(HOST, 8080, timeout=10); s = 0
        with lock:
            done += 1; bad += s >= 500 or s == 0


def report():
    last = 0
    while True:
        time.sleep(10)
        with lock: d, b = done, bad
        el = time.time() - t0
        print(f"{time.strftime('%H:%M:%S')} sent {d:>8,} · {(d - last) / 10:6.0f}/s · 5xx {b}", flush=True); last = d
        if d >= N: return


ts = [threading.Thread(target=worker, args=(k,)) for k in range(WORKERS)]
rt = threading.Thread(target=report, daemon=True); rt.start()
[t.start() for t in ts]; [t.join() for t in ts]
print(f"done: {done:,} requests in {time.time() - t0:.0f} s, 5xx {bad}", flush=True)
