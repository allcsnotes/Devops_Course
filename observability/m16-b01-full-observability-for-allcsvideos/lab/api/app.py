"""allcsvideos API, M16-B01 lab build (Flask; it stands in for the Spring Boot API, whose platform build exposes only
health and info). The edge for the students:
  GET /api/courses        the course list, from the catalog database (connection pool of POOL_SIZE)
  GET /api/ask?q=...      asks Course Copilot, timeout COPILOT_TIMEOUT seconds -> 502/504 when Copilot fails
All three signals: shared http_* metrics with exemplars at /metrics, one JSON log line per request with trace_id,
and OpenTelemetry auto-instrumentation (Flask, requests, psycopg) sending spans over OTLP."""
import json, os, queue, time

import psycopg, requests
from flask import Flask, Response, g, jsonify, request
from opentelemetry import trace
from prometheus_client import REGISTRY, Counter, Gauge, Histogram
from prometheus_client.openmetrics.exposition import CONTENT_TYPE_LATEST, generate_latest

VERSION = os.environ.get("APP_VERSION", "dev")
COPILOT = os.environ.get("COPILOT_URL", "http://copilot:8000")
COPILOT_TIMEOUT = float(os.environ.get("COPILOT_TIMEOUT", "2"))
POOL_SIZE = int(os.environ.get("POOL_SIZE", "4"))
POOL_WAIT = float(os.environ.get("POOL_WAIT", "1"))

REQS = Counter("http_requests", "HTTP requests", ["route", "status"])
LAT = Histogram("http_request_duration_seconds", "HTTP request duration", ["route"],
                buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5))
INFLIGHT = Gauge("http_requests_in_flight", "requests being served right now")
POOL_USE = Gauge("db_pool_in_use", "connections in use")
Gauge("db_pool_size", "pool size").set(POOL_SIZE)


def log(level, msg, **kv):
    ctx = trace.get_current_span().get_span_context()
    print(json.dumps({"ts": time.strftime("%H:%M:%S") + ("%.3f" % (time.time() % 1))[1:], "level": level,
                      "service": "api", "version": VERSION, "msg": msg,
                      "trace_id": format(ctx.trace_id, "032x") if ctx.is_valid else None,
                      "span_id": format(ctx.span_id, "016x") if ctx.is_valid else None, **kv}), flush=True)


pool = queue.Queue()
for _ in range(POOL_SIZE):
    while True:
        try:
            c = psycopg.connect(os.environ["DATABASE_URL"], autocommit=True, options="-c statement_timeout=1500"); break
        except psycopg.OperationalError:
            time.sleep(1)
    pool.put(c)

import logging
logging.getLogger("werkzeug").setLevel(logging.ERROR)   # no access log: our own JSON line replaces it
app = Flask(__name__)


@app.before_request
def start():
    g.t0 = time.perf_counter(); g.log = {}
    if request.path.startswith("/api/"):
        INFLIGHT.inc()


@app.after_request
def done(resp):
    if not request.path.startswith("/api/"):
        return resp
    INFLIGHT.dec()
    dur = time.perf_counter() - g.t0
    ctx = trace.get_current_span().get_span_context()
    LAT.labels(request.path).observe(dur, exemplar={"trace_id": format(ctx.trace_id, "032x")} if ctx.is_valid else None)
    REQS.labels(request.path, str(resp.status_code)).inc()
    log("error" if resp.status_code >= 500 else "info", "request", method=request.method, route=request.path,
        status=resp.status_code, duration_ms=round(dur * 1000, 1), **g.log)
    return resp


@app.get("/healthz")
def healthz():
    return {"ok": True, "version": VERSION}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(REGISTRY), content_type=CONTENT_TYPE_LATEST)


@app.get("/api/courses")
def courses():
    try:
        conn = pool.get(timeout=POOL_WAIT)
    except queue.Empty:
        g.log = {"error": "no free db connection"}
        return jsonify({"error": "busy"}), 503
    POOL_USE.inc()
    try:
        rows = conn.execute("SELECT id, title FROM courses ORDER BY id").fetchall()
    finally:
        pool.put(conn); POOL_USE.dec()
    return jsonify({"courses": [{"id": i, "title": t} for i, t in rows]})


@app.get("/api/ask")
def ask():
    q = request.args.get("q", "")
    try:
        r = requests.get(f"{COPILOT}/ask", params={"q": q}, timeout=COPILOT_TIMEOUT)
    except requests.Timeout:
        g.log = {"q": q, "error": f"copilot timed out after {COPILOT_TIMEOUT:g}s"}
        return jsonify({"error": "Course Copilot is slow, try again"}), 504
    except requests.ConnectionError as e:
        g.log = {"q": q, "error": "copilot unreachable"}
        return jsonify({"error": "Course Copilot is unavailable"}), 502
    if r.status_code != 200:
        g.log = {"q": q, "error": f"copilot answered {r.status_code}"}
        return jsonify({"error": "Course Copilot failed"}), 502
    return jsonify(r.json())


if __name__ == "__main__":
    log("info", "listening", port=8080, pool_size=POOL_SIZE)
    app.run(host="0.0.0.0", port=8080, threaded=True, use_reloader=False)
