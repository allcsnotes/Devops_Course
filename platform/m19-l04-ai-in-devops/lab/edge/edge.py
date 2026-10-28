"""allcsvideos edge services, lab build for M19-L04 (AI in DevOps). One file, two services (SERVICE env):
  storefront-bff  the storefront's backend-for-frontend: /, /courses, /course/<id>, /search?q=  -> catalog-api
  course-copilot  Course Copilot, keyword lab build, "no AI model": /ask?q=&user=  -> catalog-api
Both call the catalog API replicas round robin. Metrics: the shared course metrics (http_requests_total,
http_request_duration_seconds, http_requests_in_flight) plus upstream_errors_total. Logs: one JSON line per request.
Traces: OpenTelemetry auto-instrumentation (Flask, requests) sends spans to Tempo.
Staged on purpose (FAKE values, see the lesson): the startup line logs a FAKE API key, and Copilot logs the asker's
email address. Real systems leak exactly like this; the lesson redacts them before any model sees the logs."""
import itertools, json, logging, os, sys, time

import requests
from flask import Flask, Response, g, jsonify, request
from opentelemetry import trace
from prometheus_client import REGISTRY, Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST

SERVICE = os.environ.get("SERVICE", "storefront-bff")
VERSION = os.environ.get("APP_VERSION", "dev")
UPSTREAMS = itertools.cycle(os.environ.get("UPSTREAMS", "http://api-1:8080").split(","))
API_KEY = os.environ.get("CATALOG_API_KEY", "")

REQS = Counter("http_requests_total", "HTTP requests", ["method", "route", "status"])
LAT = Histogram("http_request_duration_seconds", "Request duration", ["route"],
                buckets=(0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0))
INFL = Gauge("http_requests_in_flight", "Requests being served right now")
UPE = Counter("upstream_errors_total", "Failed calls to an upstream service", ["upstream"])
Gauge("app_build_info", "Release running in this container", ["version"]).labels(VERSION).set(1)


class JsonLines(logging.Formatter):
    def format(self, r):
        ctx = trace.get_current_span().get_span_context()
        d = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(r.created)) + f".{int(r.msecs):03d}",
             "level": r.levelname.lower(), "service": SERVICE, "version": VERSION, "msg": r.getMessage(),
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
http = requests.Session()


def catalog(path):
    base = next(UPSTREAMS)
    try:
        r = http.get(base + path, headers={"X-Api-Key": API_KEY}, timeout=2.5)
    except requests.RequestException as e:
        UPE.labels("catalog-api").inc()
        raise RuntimeError(f"upstream catalog-api unreachable ({base}): {type(e).__name__}")
    if r.status_code >= 500:
        UPE.labels("catalog-api").inc()
        raise RuntimeError(f"upstream catalog-api returned {r.status_code} ({base}{path})")
    return r.json()


@app.before_request
def start():
    g.t0 = time.perf_counter()
    INFL.inc()


@app.after_request
def done(resp):
    INFL.dec()
    if request.path in ("/metrics", "/healthz"):
        return resp
    route = request.url_rule.rule if request.url_rule else "unknown"
    sec = time.perf_counter() - g.t0
    REQS.labels(request.method, route, str(resp.status_code)).inc()
    LAT.labels(route).observe(sec)
    f = {"route": route, "status": resp.status_code, "duration_ms": round(sec * 1000, 1)}
    f.update(getattr(g, "extra", {}))
    if getattr(g, "err", None):
        f["error"] = g.err
    log.log(logging.ERROR if resp.status_code >= 500 else logging.INFO, "request", extra={"fields": f})
    return resp


@app.get("/healthz")
def healthz():
    return {"ok": True, "version": VERSION}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(REGISTRY), content_type=CONTENT_TYPE_LATEST)


if SERVICE == "storefront-bff":
    @app.get("/")
    def home():
        c = catalog("/api/courses")["courses"]
        return jsonify({"page": "home", "featured": c[:4]})

    @app.get("/courses")
    def courses():
        return jsonify({"page": "courses", "courses": catalog("/api/courses")["courses"]})

    @app.get("/course/<int:cid>")
    def course(cid):
        return jsonify({"page": "course", "course": catalog(f"/api/courses/{cid}")})

    @app.get("/search")
    def search():
        q = request.args.get("q", "")
        g.extra = {"q": q[:300]}          # the search text is logged as typed: user input, untrusted
        hits = [c for c in catalog("/api/courses")["courses"] if q.lower() in c["title"].lower()]
        return jsonify({"page": "search", "hits": hits})
else:
    @app.get("/ask")
    def ask():
        q, user = request.args.get("q", ""), request.args.get("user", "")
        g.extra = {"user": user}           # staged on purpose: personal data (a FAKE email) in a log line
        words = [w for w in q.lower().split() if len(w) > 3]
        hits = [c for c in catalog("/api/courses")["courses"] if any(w in c["title"].lower() for w in words)]
        return jsonify({"answer": f"{len(hits)} matching courses", "model": "none (keyword lab build)"})


@app.errorhandler(Exception)
def boom(e):
    g.err = f"{type(e).__name__}: {str(e).strip().splitlines()[0]}"
    return jsonify({"error": "internal error"}), 502 if "upstream" in str(e) else 500


if __name__ == "__main__":
    # staged on purpose: a startup line that prints a (FAKE) credential, a classic leak
    log.info("starting", extra={"fields": {"port": 8080, "upstreams": os.environ.get("UPSTREAMS"),
                                           "catalog_api_key": API_KEY}})
    app.run(host="0.0.0.0", port=8080, threaded=True, use_reloader=False)
