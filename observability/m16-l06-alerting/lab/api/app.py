"""allcsvideos API, lab build (from M16-L01; M16-L06 adds http_requests_in_flight). Python 3.13, pg8000 + prometheus-client.

  GET /api/courses                 the course list: SELECT from the catalog database (fast)
  GET /api/courses?sort=popular    the same list sorted by views: aggregates the views table (slow on purpose)
  GET /metrics                     Prometheus text format (module 16, lesson 2 scrapes it)
  GET /healthz                     liveness

Connection pool: POOL_SIZE connections (default 4). A request waits at most POOL_WAIT seconds (default 1)
for a free connection, else 503 "pool timeout". Every query has a statement_timeout (default 1500 ms) -> 500.
Every request writes one JSON log line to stdout (structured logging, lesson 4).
LOG_LEVEL=debug also logs every row returned (the "log everything" pitfall).
USER_LABEL=1 adds a per-user counter (the high-cardinality pitfall).
"""
import json, os, queue, secrets, socket, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

import pg8000.native
from prometheus_client import Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST

POOL_SIZE = int(os.environ.get("POOL_SIZE", "4"))
POOL_WAIT = float(os.environ.get("POOL_WAIT", "1"))
STMT_TIMEOUT_MS = int(os.environ.get("STMT_TIMEOUT_MS", "1500"))
DEBUG = os.environ.get("LOG_LEVEL", "info") == "debug"
USER_LABEL = os.environ.get("USER_LABEL", "0") == "1"
HOST = socket.gethostname()

REQS = Counter("http_requests_total", "HTTP requests", ["route", "status"])
LAT = Histogram("http_request_duration_seconds", "HTTP request duration", ["route"],
                buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5))
INFLIGHT = Gauge("http_requests_in_flight", "requests being served right now")
POOL_USE = Gauge("db_pool_in_use", "connections in use")
POOL_WAITING = Gauge("db_pool_waiting", "requests waiting for a connection")
Gauge("db_pool_size", "pool size").set(POOL_SIZE)
POOL_TIMEOUTS = Counter("db_pool_timeouts_total", "requests that gave up waiting for a connection")
BY_USER = Counter("http_requests_by_user_total", "requests per user (DON'T)", ["user"]) if USER_LABEL else None

SQL = {
    "list": "SELECT id, title FROM courses ORDER BY id",
    "popular": "SELECT c.id, c.title, count(v.course_id) AS views FROM courses c "
               "LEFT JOIN views v ON v.course_id = c.id GROUP BY c.id, c.title ORDER BY views DESC",
}


def log(level, msg, **kv):
    print(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S") + ("%.3f" % (time.time() % 1))[1:],
                      "level": level, "service": "api", "msg": msg, **kv}), flush=True)


def connect():
    while True:
        try:
            c = pg8000.native.Connection("app", host=os.environ.get("DB_HOST", "db"), database="catalog",
                                         password=os.environ["DB_PASSWORD"])
            c.run(f"SET statement_timeout = {STMT_TIMEOUT_MS}")
            return c
        except Exception as e:
            log("warn", "db not ready", error=str(e)[:80]); time.sleep(1)


pool = queue.Queue()
for _ in range(POOL_SIZE):
    pool.put(connect())
waiting = 0
wlock = threading.Lock()


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
        global waiting
        u = urlparse(self.path); q = parse_qs(u.query)
        if u.path == "/metrics":
            return self.reply(200, generate_latest().decode(), CONTENT_TYPE_LATEST)
        if u.path == "/healthz":
            return self.reply(200, "alive\n", "text/plain")
        if u.path != "/api/courses":
            return self.reply(404, '{"error":"not found"}\n')
        route = "/api/courses?sort=popular" if q.get("sort") == ["popular"] else "/api/courses"
        user = q.get("user", ["anonymous"])[0]
        trace = secrets.token_hex(16)
        INFLIGHT.inc()
        t0 = time.perf_counter(); wait_ms = db_ms = 0; err = None
        with wlock: waiting += 1; POOL_WAITING.set(waiting)
        try:
            conn = pool.get(timeout=POOL_WAIT)
        except queue.Empty:
            conn = None
        with wlock: waiting -= 1; POOL_WAITING.set(waiting)
        wait_ms = (time.perf_counter() - t0) * 1000
        if conn is None:
            POOL_TIMEOUTS.inc(); status, body, err = 503, '{"error":"pool timeout"}\n', "no free db connection"
        else:
            POOL_USE.inc()
            t1 = time.perf_counter()
            try:
                rows = conn.run(SQL["popular" if "popular" in route else "list"])
                status = 200
                body = json.dumps({"courses": [{"id": r[0], "title": r[1]} for r in rows]}, ensure_ascii=False) + "\n"
                if DEBUG:
                    for r in rows:
                        log("debug", "row", trace_id=trace, id=r[0], title=r[1])
            except Exception as e:
                status, body = 500, '{"error":"database error"}\n'
                err = str(e.args[0].get("M", e) if e.args and isinstance(e.args[0], dict) else e)[:120]
                try:
                    conn.run("ROLLBACK")
                except Exception:
                    conn = connect()
            db_ms = (time.perf_counter() - t1) * 1000
            pool.put(conn); POOL_USE.dec()
        dur = time.perf_counter() - t0
        REQS.labels(route, str(status)).inc(); LAT.labels(route).observe(dur); INFLIGHT.dec()
        if BY_USER: BY_USER.labels(user).inc()
        kv = dict(trace_id=trace, method="GET", route=route, status=status, duration_ms=round(dur * 1000, 1),
                  pool_wait_ms=round(wait_ms, 1), db_ms=round(db_ms, 1), user=user)
        if err: kv["error"] = err
        log("error" if status >= 500 else "info", "request", **kv)
        try:
            self.reply(status, body)
        except BrokenPipeError:
            pass  # the client already gave up

    def log_message(self, *a):
        pass


log("info", "listening", port=8080, pool_size=POOL_SIZE, statement_timeout_ms=STMT_TIMEOUT_MS)
srv = ThreadingHTTPServer(("0.0.0.0", 8080), H)
srv.daemon_threads = True
srv.serve_forever()
