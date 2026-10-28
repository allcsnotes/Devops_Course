"""allcsvideos catalog API, lab build for M17-L04 (chaos engineering and disaster recovery). Python 3.13, pg8000.

  GET  /api/courses          the course list (a catalog query). If the database is down, it answers 200 from the
                             last good copy in memory, marked "stale": the course list degrades, it doesn't fail.
  POST /api/enroll           a write: one new enrollment row. Needs the database: 503 when it is down.
  GET  /metrics              Prometheus text format (the shared metrics from module 16)
  GET  /healthz              liveness: the process only, never the database (module 14, lesson 3)
"""
import json, os, socket, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

import pg8000.native
from prometheus_client import Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST

HOST = socket.gethostname()
REQS = Counter("http_requests_total", "HTTP requests", ["route", "code"])
LAT = Histogram("http_request_duration_seconds", "HTTP request duration", ["route"],
                buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5))
IN_FLIGHT = Gauge("http_requests_in_flight", "requests being handled right now")
STALE = Counter("api_stale_answers_total", "course lists served from the in-memory copy")

lock = threading.Lock()
db = None
last_good = None                          # the last course list read from the database


def conn():
    global db
    if db is None:
        db = pg8000.native.Connection("allcs", host=os.environ.get("DB_HOST", "db"), database="catalog",
                                      password=os.environ["DB_PASSWORD"], timeout=2)
    return db


def query(sql, **kw):
    global db
    with lock:
        try:
            return conn().run(sql, **kw)
        except Exception:
            try:
                db and db.close()
            except Exception:
                pass
            db = None
            raise


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, code, body, ctype="application/json", extra=None):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(b)

    def handle_api(self, route, fn):
        t0 = time.perf_counter(); IN_FLIGHT.inc()
        try:
            code, body, extra = fn()
        except Exception as e:
            code, body, extra = 503, json.dumps({"error": "database unavailable", "detail": str(e)[:60]}) + "\n", None
        REQS.labels(route, str(code)).inc(); LAT.labels(route).observe(time.perf_counter() - t0); IN_FLIGHT.dec()
        try:
            self.reply(code, body, extra=extra)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def courses(self):
        global last_good
        try:
            rows = query("SELECT id, title FROM courses ORDER BY id LIMIT 5")
            last_good = [r[1] for r in rows]
            return 200, json.dumps({"served_by": HOST, "courses": last_good}) + "\n", None
        except Exception:
            if last_good is None:
                raise
            STALE.inc()                       # degrade: the list from memory, marked stale
            return 200, json.dumps({"served_by": HOST, "stale": True, "courses": last_good}) + "\n", {"X-Stale": "true"}

    def enroll(self):
        n = int(self.headers.get("Content-Length") or 0)
        d = json.loads(self.rfile.read(n) or b"{}")
        r = query("INSERT INTO enrollments (student, course_id) VALUES (:s, :c) RETURNING id",
                  s=d.get("student", "student@example.com"), c=int(d.get("course_id", 1)))
        return 201, json.dumps({"enrollment": r[0][0], "served_by": HOST}) + "\n", None

    def do_GET(self):
        p = urlparse(self.path).path
        if p == "/metrics":
            return self.reply(200, generate_latest().decode(), CONTENT_TYPE_LATEST)
        if p == "/healthz":
            return self.reply(200, f"alive {HOST}\n", "text/plain")
        if p == "/api/courses":
            return self.handle_api("/api/courses", self.courses)
        self.reply(404, '{"error":"not found"}\n')

    def do_POST(self):
        if urlparse(self.path).path == "/api/enroll":
            return self.handle_api("/api/enroll", self.enroll)
        self.reply(404, '{"error":"not found"}\n')

    def log_message(self, *a):
        pass


print(f"allcsvideos catalog API on {HOST}:8080", flush=True)
srv = ThreadingHTTPServer(("0.0.0.0", 8080), H)
srv.daemon_threads = True
srv.serve_forever()
