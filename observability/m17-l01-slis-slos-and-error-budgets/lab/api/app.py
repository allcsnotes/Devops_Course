"""allcsvideos catalog API, lab build for M17-L01 (SLOs; from the M16 labs). Python 3.13, pg8000 + prometheus-client.

  GET /api/courses    the course list: SELECT from the catalog database
  GET /metrics        Prometheus text format
  GET /healthz        liveness (not a user request: the SLI leaves it out)

Shared metric names (module 16): http_requests_total, http_request_duration_seconds, http_requests_in_flight.
FAULT_RATE (staged on purpose, version 1.1): that share of course-list requests fails with a 500,
standing in for a bug in the new course search code. APP_VERSION is reported by /healthz.
"""
import json, os, queue, random, socket, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

import pg8000.native
from prometheus_client import Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST

POOL_SIZE = int(os.environ.get("POOL_SIZE", "4"))
VERSION = os.environ.get("APP_VERSION", "1.0")
FAULT_RATE = float(os.environ.get("FAULT_RATE", "0"))

REQS = Counter("http_requests_total", "HTTP requests", ["route", "status"])
LAT = Histogram("http_request_duration_seconds", "HTTP request duration", ["route"],
                buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5))
IN_FLIGHT = Gauge("http_requests_in_flight", "requests being handled right now")
Gauge("http_build_info", "running version", ["version"]).labels(VERSION).set(1)
for _s in ("200", "500", "503"):          # start every status at 0, so error ratios exist before the first error
    REQS.labels("/api/courses", _s)


def log(level, msg, **kv):
    print(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "level": level, "service": "api",
                      "msg": msg, **kv}), flush=True)


def connect():
    while True:
        try:
            c = pg8000.native.Connection("app", host=os.environ.get("DB_HOST", "db"), database="catalog",
                                         password=os.environ["DB_PASSWORD"])
            c.run("SET statement_timeout = 1500")
            return c
        except Exception as e:
            log("warn", "db not ready", error=str(e)[:80]); time.sleep(1)


pool = queue.Queue()
for _ in range(POOL_SIZE):
    pool.put(connect())


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, code, body, ctype="application/json"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/metrics":
            return self.reply(200, generate_latest().decode(), CONTENT_TYPE_LATEST)
        if u.path == "/healthz":
            return self.reply(200, f"alive {VERSION}\n", "text/plain")
        if u.path != "/api/courses":
            return self.reply(404, '{"error":"not found"}\n')
        route = "/api/courses"
        t0 = time.perf_counter(); IN_FLIGHT.inc(); err = None
        try:
            conn = pool.get(timeout=1)
        except queue.Empty:
            conn = None
        if conn is None:
            status, body, err = 503, '{"error":"pool timeout"}\n', "no free db connection"
        else:
            try:
                rows = conn.run("SELECT id, title FROM courses ORDER BY id")
                if FAULT_RATE and random.random() < FAULT_RATE:
                    raise RuntimeError("search: course level is NULL")   # the staged v1.1 bug
                status = 200
                body = json.dumps({"courses": [{"id": r[0], "title": r[1]} for r in rows]}, ensure_ascii=False) + "\n"
            except Exception as e:
                status, body, err = 500, '{"error":"internal error"}\n', str(e)[:120]
            pool.put(conn)
        dur = time.perf_counter() - t0
        REQS.labels(route, str(status)).inc(); LAT.labels(route).observe(dur); IN_FLIGHT.dec()
        if err:
            log("error", "request", route=route, status=status, duration_ms=round(dur * 1000, 1), error=err)
        try:
            self.reply(status, body)
        except BrokenPipeError:
            pass

    def log_message(self, *a):
        pass


log("info", "listening", port=8080, version=VERSION, fault_rate=FAULT_RATE)
srv = ThreadingHTTPServer(("0.0.0.0", 8080), H)
srv.daemon_threads = True
srv.serve_forever()
