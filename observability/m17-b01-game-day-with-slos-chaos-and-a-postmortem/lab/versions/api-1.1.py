"""allcsvideos catalog API, lab build for the M17 game day. Python 3.13, pg8000, prometheus-client.

  GET /api/courses       the course list (a catalog query). If the database doesn't answer within its statement
                         timeout, it answers 200 from the last good copy in memory, marked stale (lesson 4's design).
  GET /api/ask?q=...     Course Copilot: the API asks the copilot service and passes the answer on.
  GET /healthz           liveness: the process only, never the database (module 14, lesson 3)
  :9100/metrics          Prometheus metrics, served on their own port
Requests are handled by a fixed pool of WORKERS threads, like gunicorn --threads.
"""
import json, os, random, socket, threading, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, HTTPServer

import pg8000.native
from pg8000.exceptions import DatabaseError
from prometheus_client import Counter, Gauge, Histogram, start_http_server

VERSION = "1.1"
HOST = socket.gethostname()
WORKERS = 8
COPILOT = os.environ.get("COPILOT_URL", "http://copilot:8000")

REQS = Counter("http_requests_total", "HTTP requests", ["route", "code"])
LAT = Histogram("http_request_duration_seconds", "HTTP request duration", ["route"],
                buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10))
BUSY = Gauge("api_workers_busy", "worker threads handling a request right now")
STALE = Counter("api_stale_answers_total", "course lists served from the in-memory copy")
CALLS = Counter("api_copilot_calls_total", "calls from the API to Course Copilot", ["result"])
CALL_LAT = Histogram("api_copilot_call_seconds", "time spent waiting for Course Copilot", buckets=(.01, .05, .1, .5, 1, 2, 5, 10))
Gauge("app_build_info", "running version", ["version"]).labels(VERSION).set(1)
for r in ("/api/courses", "/api/ask"):
    for c in ("200", "500", "503"):
        REQS.labels(r, c)                     # every series exists at 0, so error ratios work at baseline

lock = threading.Lock()
db = None
last_good = None


def flag(name):                               # feature flags: a file the ops team can change (module 9, lesson 3)
    try:
        return json.load(open("/flags/flags.json")).get(name, True)
    except Exception:
        return True


def query(sql):
    global db
    with lock:
        try:
            if db is None:
                db = pg8000.native.Connection("allcs", host="db", database="catalog", password=os.environ["DB_PASSWORD"],
                                              timeout=3, application_name=f"catalog-api {HOST}")
                db.run("SET statement_timeout = '100ms'")   # lesson 4's finding: fail fast, then serve the stale copy
            return db.run(sql)
        except DatabaseError:
            raise                             # the query failed, the connection is still fine
        except Exception:
            try:
                db and db.close()
            except Exception:
                pass
            db = None
            raise


def courses():
    global last_good
    try:
        rows = [r[0] for r in query("SELECT title FROM courses ORDER BY id LIMIT 10")]
        last_good = rows[:5]
    except Exception:
        if last_good is None:
            raise
        STALE.inc()
        return 200, {"served_by": HOST, "version": VERSION, "stale": True, "courses": last_good}
    featured = rows[random.randint(0, len(rows))]       # 1.1: a featured course on the list
    return 200, {"served_by": HOST, "version": VERSION, "courses": last_good, "featured": featured}


def ask(q):
    if not flag("ask"):
        return 503, {"error": "Course Copilot is switched off", "served_by": HOST}
    t0 = time.perf_counter()
    try:
        url = COPILOT + "/ask?" + urllib.parse.urlencode({"q": q})
        with urllib.request.urlopen(url, timeout=10) as r:
            ans = json.loads(r.read())
        CALLS.labels("ok").inc()
        return 200, {"served_by": HOST, **ans}
    except Exception as e:
        CALLS.labels("error").inc()
        return 503, {"error": "Course Copilot unavailable", "detail": str(e)[:60], "served_by": HOST}
    finally:
        CALL_LAT.observe(time.perf_counter() - t0)


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, code, obj, ctype="application/json"):
        b = (obj if isinstance(obj, str) else json.dumps(obj) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == "/healthz":
            return self.reply(200, f"alive {HOST} {VERSION}\n", "text/plain")
        if u.path not in ("/api/courses", "/api/ask"):
            return self.reply(404, {"error": "not found"})
        t0 = time.perf_counter()
        try:
            if u.path == "/api/courses":
                code, body = courses()
            else:
                code, body = ask(urllib.parse.parse_qs(u.query).get("q", ["devops"])[0])
        except Exception as e:
            code, body = 500, {"error": str(e)[:80], "served_by": HOST}
        REQS.labels(u.path, str(code)).inc()
        LAT.labels(u.path).observe(time.perf_counter() - t0)
        try:
            self.reply(code, body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *a):
        pass


class PoolServer(HTTPServer):                 # a fixed pool of worker threads
    pool = ThreadPoolExecutor(WORKERS)

    def process_request(self, req, addr):
        self.pool.submit(self.work, req, addr)

    def work(self, req, addr):
        BUSY.inc()
        try:
            self.finish_request(req, addr)
        except Exception:
            pass
        finally:
            BUSY.dec()
            self.shutdown_request(req)


start_http_server(9100)
print(f"catalog-api {VERSION} on {HOST}:8080, {WORKERS} workers", flush=True)
PoolServer(("0.0.0.0", 8080), H).serve_forever()
