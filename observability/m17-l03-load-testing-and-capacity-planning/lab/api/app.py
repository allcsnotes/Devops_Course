"""allcsvideos API, lab build for M17-L03 (load testing). Python 3.13, pg8000 + prometheus-client.

  GET /api/courses?user=U    the course list, ranked for user U: one catalog query, then ranking work
                             (WORK rounds of SHA-256 over the user's watch history: real CPU per request).
                             The ranked list is cached per user for CACHE_TTL seconds (default 60).
  GET /metrics               Prometheus text format (the shared metrics from module 16)
  GET /healthz               liveness

One worker ranks at a time, like a single gunicorn worker (lesson learned in module 14, lesson 4).
A request that waited in the queue longer than MAX_WAIT seconds (default 1.5) gets 503 "busy".
"""
import hashlib, json, os, socket, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

import pg8000.native
from prometheus_client import Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST

WORK = int(os.environ.get("WORK", "100000"))
MAX_WAIT = float(os.environ.get("MAX_WAIT", "1.5"))
CACHE_TTL = float(os.environ.get("CACHE_TTL", "60"))
VERSION = os.environ.get("APP_VERSION", "1.0")
HOST = socket.gethostname()

REQS = Counter("http_requests_total", "HTTP requests", ["route", "status"])
LAT = Histogram("http_request_duration_seconds", "HTTP request duration", ["route"],
                buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5))
IN_FLIGHT = Gauge("http_requests_in_flight", "requests being handled right now")
CACHE = Counter("api_cache_requests_total", "ranked-list cache lookups", ["result"])
Gauge("http_build_info", "running version", ["version"]).labels(VERSION).set(1)

WORKER = threading.Semaphore(1)          # one request ranks at a time; the rest wait in line
cache, clock = {}, threading.Lock()


def connect():
    while True:
        try:
            return pg8000.native.Connection("app", host=os.environ.get("DB_HOST", "db"), database="catalog",
                                            password=os.environ["DB_PASSWORD"])
        except Exception as e:
            print("db not ready:", str(e)[:80], flush=True); time.sleep(1)


db = connect()


def rank(user):
    rows = db.run("SELECT id, title FROM courses ORDER BY id")      # the catalog query
    h = f"{user}:watched".encode()
    for _ in range(WORK):                                            # the CPU-heavy part: ranking
        h = hashlib.sha256(h).digest()
    k = h[0] % len(rows)
    return rows[k:] + rows[:k]


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, code, body, ctype="application/json"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        u = urlparse(self.path); q = parse_qs(u.query)
        if u.path == "/metrics":
            return self.reply(200, generate_latest().decode(), CONTENT_TYPE_LATEST)
        if u.path == "/healthz":
            return self.reply(200, f"alive {VERSION}\n", "text/plain")
        if u.path != "/api/courses":
            return self.reply(404, '{"error":"not found"}\n')
        user = q.get("user", ["anonymous"])[0]
        t0 = time.perf_counter(); IN_FLIGHT.inc()
        with clock:
            hit = cache.get(user)
        if hit and time.time() - hit[0] < CACHE_TTL:
            CACHE.labels("hit").inc(); status, rows = 200, hit[1]
        else:
            CACHE.labels("miss").inc()
            with WORKER:
                if time.perf_counter() - t0 > MAX_WAIT:      # the user gave up long ago: don't burn CPU for nobody
                    status, rows = 503, None
                else:
                    rows = rank(user); status = 200
                    with clock:
                        cache[user] = (time.time(), rows)
        body = json.dumps({"user": user, "courses": [r[1] for r in rows[:5]]}, ensure_ascii=False) + "\n" if rows else '{"error":"busy"}\n'
        dur = time.perf_counter() - t0
        REQS.labels("/api/courses", str(status)).inc(); LAT.labels("/api/courses").observe(dur); IN_FLIGHT.dec()
        try:
            self.reply(status, body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # the client already gave up

    def log_message(self, *a):
        pass


print(f"allcsvideos API {VERSION} listening on :8080, work={WORK}, max_wait={MAX_WAIT}s, cache_ttl={CACHE_TTL:g}s", flush=True)
srv = ThreadingHTTPServer(("0.0.0.0", 8080), H)
srv.daemon_threads = True
srv.request_queue_size = 512
srv.serve_forever()
