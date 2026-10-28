"""allcsvideos lab services for M16-L05 (distributed tracing). One image, three roles, chosen by SERVICE:
  bff      storefront-bff: the backend for the storefront. GET /catalog?user=u3181 builds the course page by asking the api
  api      the allcsvideos API: GET /courses asks catalog for the courses and the user's enrollments
  catalog  catalog-service: reads PostgreSQL. For each course on the page it checks "is this user enrolled?"
Tracing comes from OpenTelemetry auto-instrumentation (opentelemetry-instrument): Flask, requests, psycopg and logging
are patched at startup, so this file has no tracing code except one manual span in catalog (the API, used directly).
Lab knobs (staged on purpose): QUERY_MODE=per_course|batched, FAULT_RATE, LEGACY_CLIENT=1 (api calls catalog with
urllib, a client the auto-instrumentation does not cover), SPAN_PER_ID=1 (a badly named manual span)."""
import json, logging, os, random, sys, time, urllib.request

import psycopg, requests
from flask import Flask, Response, g, jsonify, request
from opentelemetry import trace
from prometheus_client import REGISTRY, Histogram
from prometheus_client.openmetrics.exposition import CONTENT_TYPE_LATEST, generate_latest

SERVICE = os.environ.get("SERVICE", "api")
API = os.environ.get("API_URL", "http://api:8080")
CATALOG = os.environ.get("CATALOG_URL", "http://catalog:8080")
DSN = os.environ.get("DATABASE_URL", "")
QUERY_MODE = os.environ.get("QUERY_MODE", "per_course")
FAULT_RATE = float(os.environ.get("FAULT_RATE", "0"))
LEGACY_CLIENT = os.environ.get("LEGACY_CLIENT", "0") == "1"
SPAN_PER_ID = os.environ.get("SPAN_PER_ID", "0") == "1"

tracer = trace.get_tracer("allcsvideos.catalog")


class JsonLines(logging.Formatter):
    """One JSON object per line on stdout, with the trace and span IDs of the request being handled."""
    def format(self, r):
        ctx = trace.get_current_span().get_span_context()
        d = {"ts": time.strftime("%H:%M:%S", time.localtime(r.created)) + f".{int(r.msecs):03d}", "level": r.levelname.lower(),
             "service": SERVICE, "msg": r.getMessage(),
             "trace_id": format(ctx.trace_id, "032x") if ctx.is_valid else None,
             "span_id": format(ctx.span_id, "016x") if ctx.is_valid else None}
        d.update(getattr(r, "fields", {}))
        if r.exc_info:
            d["error"] = f"{r.exc_info[0].__name__}: {r.exc_info[1]}"
        return json.dumps(d)


log = logging.getLogger("allcsvideos")
log.setLevel(logging.INFO)
_h = logging.StreamHandler(sys.stdout)
_h.setFormatter(JsonLines())
log.addHandler(_h)
logging.getLogger("werkzeug").setLevel(logging.ERROR)

app = Flask(__name__)
LAT = Histogram("http_request_duration_seconds", "Request duration", ["route"],
                buckets=(0.05, 0.1, 0.25, 0.5, 1.0, 2.5))


@app.before_request
def start():
    g.t0 = time.perf_counter()


@app.after_request
def done(resp):
    if request.path in ("/healthz", "/metrics"):
        return resp
    ms = round((time.perf_counter() - g.t0) * 1000, 1)
    ctx = trace.get_current_span().get_span_context()
    if SERVICE == "bff":
        LAT.labels(request.path).observe(ms / 1000, exemplar={"trace_id": format(ctx.trace_id, "032x")})
    lvl = logging.ERROR if resp.status_code >= 500 else logging.INFO
    # logging middleware: also record the traceparent header exactly as it arrived on the wire
    log.log(lvl, "request", extra={"fields": {"method": request.method, "path": request.path, "status": resp.status_code,
                                              "duration_ms": ms, "traceparent_in": request.headers.get("traceparent")}})
    return resp


@app.get("/healthz")
def healthz():
    return {"ok": True}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(REGISTRY), content_type=CONTENT_TYPE_LATEST)


# ---------- storefront-bff ----------
@app.get("/catalog")
def catalog_page():
    user = request.args.get("user", "anonymous")
    r = requests.get(f"{API}/courses", params={"user": user}, timeout=5)
    if r.status_code != 200:
        return jsonify({"error": "catalog unavailable"}), 502
    courses = r.json()["courses"]
    return jsonify({"user": user, "cards": len(courses),
                    "enrolled": [c["id"] for c in courses if c["enrolled"]]})


# ---------- api ----------
@app.get("/courses")
def courses():
    if SERVICE == "catalog":
        return catalog_courses()
    user = request.args.get("user", "anonymous")
    url = f"{CATALOG}/courses?user={user}"
    if LEGACY_CLIENT:
        # staged: a hand-written client on urllib. Nothing patches it, so no traceparent header is sent.
        with urllib.request.urlopen(urllib.request.Request(url), timeout=5) as resp:
            body, code = json.loads(resp.read()), resp.status
    else:
        r = requests.get(url, timeout=5)
        body, code = r.json(), r.status_code
    if code != 200:
        return jsonify({"error": "catalog failed"}), 502
    return jsonify(body)


# ---------- catalog-service ----------
def catalog_courses():
    user = request.args.get("user", "anonymous")
    sid = int(user[1:]) if user[1:].isdigit() else -1
    with psycopg.connect(DSN) as conn:
        rows = conn.execute("SELECT id, title, price_inr FROM courses ORDER BY id").fetchall()
        with tracer.start_as_current_span("check enrollments") as span:
            span.set_attribute("app.user_id", user)
            span.set_attribute("app.courses_count", len(rows))
            span.set_attribute("app.query_mode", QUERY_MODE)
            if random.random() < FAULT_RATE:
                span.add_event("replica unavailable", {"app.replica": "catalog-db-2"})
                raise RuntimeError("catalog replica unavailable (staged fault)")
            if QUERY_MODE == "batched":
                ids = [r[0] for r in rows]
                got = conn.execute("SELECT course_id FROM enrollments WHERE student_id = %s AND course_id = ANY(%s)",
                                   (sid, ids)).fetchall()
                enrolled = {r[0] for r in got}
            else:
                enrolled = set()
                for cid, _, _ in rows:
                    if SPAN_PER_ID:
                        with tracer.start_as_current_span(f"check course {cid} for {user}"):
                            pass
                    hit = conn.execute("SELECT 1 FROM enrollments WHERE student_id = %s AND course_id = %s LIMIT 1",
                                       (sid, cid)).fetchone()
                    if hit:
                        enrolled.add(cid)
            span.add_event("enrollments checked", {"app.enrolled_count": len(enrolled)})
    if len(rows) and QUERY_MODE != "batched":
        log.info("page built", extra={"fields": {"user": user, "queries": len(rows) + 1}})
    return jsonify({"courses": [{"id": i, "title": t, "price_inr": p, "enrolled": i in enrolled} for i, t, p in rows]})


@app.errorhandler(Exception)
def boom(e):
    log.exception("unhandled error", extra={"fields": {"path": request.path}})
    return jsonify({"error": "internal error"}), 500


if __name__ == "__main__":
    log.info("listening", extra={"fields": {"port": 8080}})
    app.run(host="0.0.0.0", port=8080, threaded=True, use_reloader=False)
