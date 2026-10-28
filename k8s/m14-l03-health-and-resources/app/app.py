"""allcsvideos API, built to stage failures for this lesson. Python standard library only.

Controllable behaviour, so every failure in the lesson can be staged for real:
  GET  /                 the course catalog (JSON); needs the catalog lock
  GET  /healthz          liveness: 200 "alive" when a request can still take the catalog lock
  GET  /readyz           readiness: 200 "ready", or 503 "draining" after POST /admin/drain
  GET  /healthz/deep     the BAD liveness check: also opens a TCP connection to the database (DB_HOST:5432)
  GET  /work?ms=N        burns N ms of CPU for one request (latency under a CPU limit)
  POST /admin/deadlock   two threads grab the catalog lock and never let go: the process lives, requests hang
  POST /admin/drain      readiness says 503 from now on (POST /admin/undrain to undo)
  POST /admin/leak       keeps allocating STEP_MB every 0.5 s and never frees it (a memory leak)
  POST /admin/burn       spins one CPU core for ?seconds=N (default 120)
STARTUP_SECONDS (default 2): warm-up before the port opens, like loading a big catalog or a model.
"""
import os, signal, socket, sys, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

POD = socket.gethostname()
VERSION = os.environ.get("APP_VERSION", "1.0.0")
STARTUP = float(os.environ.get("STARTUP_SECONDS", "2"))
STEP_MB = int(os.environ.get("STEP_MB", "4"))
DB_HOST = os.environ.get("DB_HOST", "db")
LOCK = threading.Lock()          # the catalog lock
DRAIN = threading.Event()
LEAK = []


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def deadlock():
    LOCK.acquire()               # thread 1 takes the catalog lock ...
    log("deadlock: catalog lock taken and never released")
    threading.Event().wait()     # ... and waits forever for something that never comes


def leak():
    while True:
        LEAK.append(bytearray(STEP_MB * 1024 * 1024))   # bytearray is zero-filled: real, resident memory
        log(f"leak: holding {len(LEAK) * STEP_MB} MiB")
        time.sleep(0.5)


def burn(seconds):
    log(f"burn: spinning one core for {seconds:g} s")
    end = time.time() + seconds
    while time.time() < end:
        pass
    log("burn: done")


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, code, body, ctype="text/plain"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("X-App-Version", VERSION)
        self.send_header("X-Pod", POD)
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/":
            with LOCK:
                return self.reply(200, '{"service":"allcsvideos-api","courses":["DSA","System Design","DevOps"],"pod":"%s"}\n' % POD, "application/json")
        if u.path == "/healthz":
            with LOCK:
                return self.reply(200, "alive\n")
        if u.path == "/readyz":
            if DRAIN.is_set():
                return self.reply(503, "draining\n")
            with LOCK:
                return self.reply(200, "ready\n")
        if u.path == "/healthz/deep":
            try:
                socket.create_connection((DB_HOST, 5432), timeout=1).close()
            except OSError as e:
                return self.reply(503, f"database unreachable: {e}\n")
            return self.reply(200, "alive, database reachable\n")
        if u.path == "/work":
            ms = float(parse_qs(u.query).get("ms", ["50"])[0])
            t0 = time.thread_time()
            while (time.thread_time() - t0) * 1000 < ms:
                pass
            return self.reply(200, f"worked {ms:g} ms of CPU\n")
        self.reply(404, "not found\n")

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/admin/deadlock":
            threading.Thread(target=deadlock, daemon=True).start()
            return self.reply(200, "deadlock staged: requests will hang\n")
        if u.path == "/admin/drain":
            DRAIN.set(); log("drain: readiness now answers 503")
            return self.reply(200, "draining\n")
        if u.path == "/admin/undrain":
            DRAIN.clear(); log("undrain: readiness answers 200 again")
            return self.reply(200, "ready again\n")
        if u.path == "/admin/leak":
            threading.Thread(target=leak, daemon=True).start()
            return self.reply(200, f"leak started: +{STEP_MB} MiB every 0.5 s\n")
        if u.path == "/admin/burn":
            s = float(parse_qs(u.query).get("seconds", ["120"])[0])
            threading.Thread(target=burn, args=(s,), daemon=True).start()
            return self.reply(200, f"burning one core for {s:g} s\n")
        self.reply(404, "not found\n")

    def log_message(self, *a):
        pass


signal.signal(signal.SIGTERM, lambda *_: (log("SIGTERM: shutting down"), sys.exit(0)))
log(f"allcsvideos API {VERSION} starting, warm-up {STARTUP:g} s")
t = 0
while t < STARTUP:
    step = min(10, STARTUP - t)
    time.sleep(step); t += step
    if STARTUP > 10:
        log(f"warming up: loading the catalog, {t:g} of {STARTUP:g} s")
srv = ThreadingHTTPServer(("0.0.0.0", 8080), H)
srv.daemon_threads = True
log("listening on :8080")
srv.serve_forever()
