"""allcsvideos catalog API, lab build (from M17-L02, reused in M19-L04). One file, two releases:
  1.4.2  GET /api/courses lists the courses (one small query)
  1.5.0  also adds a "trending this week" count per course. Staged bug, on purpose: that query scans all
         2,000,000 enrollments on every request (no index on enrolled_at), so under real traffic it queues
         and hits the 1 second statement timeout -> 500s.
The release is baked into the image (APP_VERSION build arg). Metrics: the shared course metrics
http_requests_total, http_request_duration_seconds, http_requests_in_flight. Logs: one JSON line per request.
Traces: OpenTelemetry auto-instrumentation (Flask, psycopg) sends spans to Tempo over OTLP."""
import json, logging, os, sys, time

import psycopg
from flask import Flask, Response, g, jsonify, request
from opentelemetry import trace
from prometheus_client import REGISTRY, Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST

VERSION = os.environ.get("APP_VERSION", "dev")
DSN = os.environ.get("DATABASE_URL", "")

REQS = Counter("http_requests_total", "HTTP requests", ["method", "route", "status"])
LAT = Histogram("http_request_duration_seconds", "Request duration", ["route"],
                buckets=(0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0))
INFL = Gauge("http_requests_in_flight", "Requests being served right now")
Gauge("app_build_info", "Release running in this container", ["version"]).labels(VERSION).set(1)


class JsonLines(logging.Formatter):
    def format(self, r):
        ctx = trace.get_current_span().get_span_context()
        d = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(r.created)) + f".{int(r.msecs):03d}",
             "level": r.levelname.lower(), "service": "catalog-api", "version": VERSION, "msg": r.getMessage(),
             "trace_id": format(ctx.trace_id, "032x") if ctx.is_valid else None}
        d.update(getattr(r, "fields", {}))
        return json.dumps(d)


log = logging.getLogger("allcsvideos")
log.setLevel(logging.INFO)
_h = logging.StreamHandler(sys.stdout)
_h.setFormatter(JsonLines())
log.addHandler(_h)
logging.getLogger("werkzeug").setLevel(logging.ERROR)

app = Flask(__name__)


def db():
    # fake lab DSN; every query gets a 1 second statement timeout
    return psycopg.connect(DSN, options="-c statement_timeout=1000", connect_timeout=3)


@app.before_request
def start():
    g.t0 = time.perf_counter()
    if request.path.startswith("/api/"):
        INFL.inc()


@app.after_request
def done(resp):
    if not request.path.startswith("/api/"):
        return resp
    INFL.dec()
    route = request.url_rule.rule if request.url_rule else "unknown"
    sec = time.perf_counter() - g.t0
    REQS.labels(request.method, route, str(resp.status_code)).inc()
    LAT.labels(route).observe(sec)
    f = {"route": route, "status": resp.status_code, "duration_ms": round(sec * 1000, 1)}
    if getattr(g, "err", None):
        f["error"] = g.err
    log.log(logging.ERROR if resp.status_code >= 500 else logging.INFO, "request", extra={"fields": f})
    return resp


@app.get("/healthz")
def healthz():
    return {"ok": True, "version": VERSION}   # only says the process is up (see the pitfalls)


@app.get("/metrics")
def metrics():
    return Response(generate_latest(REGISTRY), content_type=CONTENT_TYPE_LATEST)


@app.get("/api/courses")
def courses():
    with db() as conn:
        rows = conn.execute("SELECT id, title, price_inr FROM courses ORDER BY id").fetchall()
        trending = {}
        if VERSION >= "1.5.0":
            # new in 1.5.0: "trending this week"
            trending = dict(conn.execute(
                "SELECT course_id, count(*) FROM enrollments "
                "WHERE enrolled_at > now() - interval '7 days' GROUP BY course_id").fetchall())
    return jsonify({"version": VERSION, "courses": [
        {"id": i, "title": t, "price_inr": p, **({"trending": trending.get(i, 0)} if trending else {})} for i, t, p in rows]})


@app.get("/api/courses/<int:cid>")
def course(cid):
    with db() as conn:
        r = conn.execute("SELECT id, title, price_inr FROM courses WHERE id = %s", (cid,)).fetchone()
    if not r:
        return jsonify({"error": "not found"}), 404
    return jsonify({"id": r[0], "title": r[1], "price_inr": r[2]})


@app.errorhandler(Exception)
def boom(e):
    g.err = f"{type(e).__name__}: {str(e).strip().splitlines()[0]}"
    return jsonify({"error": "internal error"}), 500


if __name__ == "__main__":
    log.info("starting", extra={"fields": {"port": 8080}})
    app.run(host="0.0.0.0", port=8080, threaded=True, use_reloader=False)
