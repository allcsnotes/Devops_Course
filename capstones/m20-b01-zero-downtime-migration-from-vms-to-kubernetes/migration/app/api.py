"""allcsvideos catalog API, lab build for M20-B01 (zero-downtime migration from VMs to Kubernetes). Python, pg8000.
One codebase, two homes: a systemd service on the VMs (web-01, web-02) and a container image in Kubernetes.

  GET  /api/courses     the course list (a catalog query)
  POST /api/login       a student logs in: the answer sets a session cookie signed with SESSION_SECRET
  GET  /api/me          who am I: needs a valid session cookie, else 401
  POST /api/progress    a write: one lesson-progress row
  GET  /healthz         liveness: the process only, never the database (module 14, lesson 3)
  GET  /readyz          readiness: the connection pool is open and we are not shutting down
  GET  /metrics         Prometheus text format (the shared metric names from module 16)

Config comes only from the environment (on the VMs: an EnvironmentFile written by Ansible; in Kubernetes: a ConfigMap
and a Secret): DB_HOST, DB_PASSWORD, DB_POOL, SESSION_SECRET, APP_VERSION.
Graceful shutdown on SIGTERM: readiness turns 503, the listener closes, requests in flight finish, then the pool closes.
"""
import base64, hashlib, hmac, json, os, queue, signal, socket, sys, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

import pg8000.native
from prometheus_client import Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST

HOST = socket.gethostname()
VERSION = os.environ.get("APP_VERSION", "dev")
SECRET = os.environ["SESSION_SECRET"].encode()
POOL_SIZE = int(os.environ.get("DB_POOL", "10"))
REQS = Counter("http_requests_total", "HTTP requests", ["route", "code"])
LAT = Histogram("http_request_duration_seconds", "HTTP request duration", ["route"],
                buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5))
IN_FLIGHT = Gauge("http_requests_in_flight", "requests being handled right now")
POOL_OPEN = Gauge("db_pool_connections", "database connections this process holds open")

draining = threading.Event()


def connect():
    return pg8000.native.Connection("allcs", host=os.environ.get("DB_HOST", "db"), database="catalog",
                                    password=os.environ["DB_PASSWORD"], timeout=3)


# the connection pool is opened in full at startup (like HikariCP's default), and the app refuses to start without it
pool = queue.Queue()
for i in range(POOL_SIZE):
    try:
        pool.put(connect())
    except Exception as e:
        msg = e.args[0].get("M", str(e)) if e.args and isinstance(e.args[0], dict) else str(e)
        print(f"cannot open database connection {i + 1} of {POOL_SIZE}: {msg}", flush=True)
        sys.exit(1)
POOL_OPEN.set(POOL_SIZE)


def query(sql, **kw):
    try:
        c = pool.get(timeout=2)
    except queue.Empty:
        raise RuntimeError("no free database connection")
    try:
        return c.run(sql, **kw)
    except Exception:
        try:
            c.close()
        except Exception:
            pass
        c = connect()
        raise
    finally:
        pool.put(c)


def sign(student):
    s = base64.urlsafe_b64encode(student.encode()).decode().rstrip("=")
    return s + "." + hmac.new(SECRET, s.encode(), hashlib.sha256).hexdigest()[:32]


def verify(cookie):
    try:
        s, mac = cookie.split(".", 1)
    except ValueError:
        return None
    good = hmac.new(SECRET, s.encode(), hashlib.sha256).hexdigest()[:32]
    if not hmac.compare_digest(mac, good):
        return None
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4)).decode()


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = 5                                   # an idle keep-alive connection is closed after 5 seconds
    disable_nagle_algorithm = True                # headers and body leave at once (no 40 ms delayed-ACK stall)

    def reply(self, code, body, ctype="application/json", extra=None):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("X-Served-By", HOST)
        self.send_header("X-App-Version", VERSION)
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        if draining.is_set():                     # shutting down: tell the client not to reuse this connection
            self.send_header("Connection", "close")
            self.close_connection = True
        self.end_headers()
        self.wfile.write(b)

    def api(self, route, fn):
        t0 = time.perf_counter(); IN_FLIGHT.inc()
        try:
            code, body, extra = fn()
        except Exception as e:
            code, body, extra = 503, json.dumps({"error": "unavailable", "detail": str(e)[:60]}) + "\n", None
        REQS.labels(route, str(code)).inc(); LAT.labels(route).observe(time.perf_counter() - t0); IN_FLIGHT.dec()
        try:
            self.reply(code, body, extra=extra)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def courses(self):
        rows = query("SELECT id, title FROM courses ORDER BY id LIMIT 5")
        return 200, json.dumps({"served_by": HOST, "courses": [r[1] for r in rows]}) + "\n", None

    def login(self):
        student = self.body().get("student", "student@example.com")
        return 200, json.dumps({"student": student}) + "\n", {"Set-Cookie": f"session={sign(student)}; Path=/; HttpOnly"}

    def me(self):
        ck = {}
        for part in (self.headers.get("Cookie") or "").split(";"):
            if "=" in part:
                k, v = part.strip().split("=", 1); ck[k] = v
        student = verify(ck.get("session", ""))
        if not student:
            return 401, json.dumps({"error": "session not valid"}) + "\n", None
        return 200, json.dumps({"student": student, "served_by": HOST}) + "\n", None

    def progress(self):
        d = self.body()
        r = query("INSERT INTO progress (student, lesson, run) VALUES (:s, :l, :r) RETURNING id",
                  s=d.get("student", "student@example.com"), l=int(d.get("lesson", 1)), r=d.get("run", "manual"))
        return 201, json.dumps({"id": r[0][0], "served_by": HOST}) + "\n", None

    def do_GET(self):
        p = urlparse(self.path).path
        if p == "/metrics":
            return self.reply(200, generate_latest().decode(), CONTENT_TYPE_LATEST)
        if p == "/healthz":
            return self.reply(200, f"alive {HOST}\n", "text/plain")
        if p == "/readyz":
            return self.reply(503 if draining.is_set() else 200, "draining\n" if draining.is_set() else "ready\n", "text/plain")
        if p == "/api/courses":
            return self.api("/api/courses", self.courses)
        if p == "/api/me":
            return self.api("/api/me", self.me)
        self.reply(404, '{"error":"not found"}\n')

    def do_POST(self):
        p = urlparse(self.path).path
        if p == "/api/progress":
            return self.api("/api/progress", self.progress)
        if p == "/api/login":
            return self.api("/api/login", self.login)
        self.reply(404, '{"error":"not found"}\n')

    def log_message(self, *a):
        pass


srv = ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), H)
srv.daemon_threads = False                        # on shutdown, wait for every request thread to finish
srv.block_on_close = True


def on_sigterm(*_):
    print(f"SIGTERM: draining {HOST}, {int(IN_FLIGHT._value.get())} requests in flight", flush=True)
    draining.set()
    threading.Thread(target=srv.shutdown, daemon=True).start()


signal.signal(signal.SIGTERM, on_sigterm)
print(f"allcsvideos catalog API {VERSION} on {HOST}:8080, {POOL_SIZE} database connections open", flush=True)
srv.serve_forever()
srv.server_close()                                # joins the request threads: in-flight requests finish
while not pool.empty():
    pool.get().close()
print(f"stopped cleanly: {HOST}", flush=True)
