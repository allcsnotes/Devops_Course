"""Course Copilot (no AI model), M16-B01 lab build: answers "which course covers X?" from the catalog database.
All three signals, the M16 way:
  metrics  the shared http_* names (M16-L03) at /metrics, latency buckets carry exemplars (a trace ID per bucket)
  logs     one JSON line per request on stdout, with trace_id and span_id (M16-L04, M16-L05)
  traces   OpenTelemetry auto-instrumentation (opentelemetry-instrument): FastAPI and psycopg spans, sent over OTLP
Config (environment):
  APP_VERSION         shown by /health and in every log line
  SEARCH_TRANSCRIPTS  1 = also search lesson transcripts (the version 1.1 feature)
  POOL_SIZE, POOL_WAIT, STMT_TIMEOUT_MS   connection pool (4), wait for a connection (1 s), statement timeout (1000 ms)
"""
import json, os, queue, sys, threading, time

import psycopg
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from opentelemetry import trace
from prometheus_client import REGISTRY, Counter, Gauge, Histogram
from prometheus_client.openmetrics.exposition import CONTENT_TYPE_LATEST, generate_latest

VERSION = os.environ.get("APP_VERSION", "dev")
TRANSCRIPTS = os.environ.get("SEARCH_TRANSCRIPTS", "0") == "1"
DSN = os.environ["DATABASE_URL"]
POOL_SIZE = int(os.environ.get("POOL_SIZE", "4"))
POOL_WAIT = float(os.environ.get("POOL_WAIT", "1"))
STMT_TIMEOUT_MS = int(os.environ.get("STMT_TIMEOUT_MS", "1000"))

REQUESTS = Counter("http_requests", "HTTP requests", ["route", "status"])
IN_FLIGHT = Gauge("http_requests_in_flight", "requests being handled right now")
LATENCY = Histogram("http_request_duration_seconds", "HTTP request duration", ["route"],
                    buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5))
POOL_USE = Gauge("db_pool_in_use", "connections in use")
Gauge("db_pool_size", "pool size").set(POOL_SIZE)


def log(level, msg, **kv):
    ctx = trace.get_current_span().get_span_context()
    print(json.dumps({"ts": time.strftime("%H:%M:%S") + ("%.3f" % (time.time() % 1))[1:], "level": level,
                      "service": "copilot", "version": VERSION, "msg": msg,
                      "trace_id": format(ctx.trace_id, "032x") if ctx.is_valid else None,
                      "span_id": format(ctx.span_id, "016x") if ctx.is_valid else None, **kv}), flush=True)


pool = queue.Queue()
for _ in range(POOL_SIZE):
    while True:
        try:
            c = psycopg.connect(DSN, autocommit=True, options=f"-c statement_timeout={STMT_TIMEOUT_MS}"); break
        except psycopg.OperationalError:
            time.sleep(1)
    pool.put(c)

app = FastAPI(title="Course Copilot")


@app.middleware("http")
async def measure(request: Request, call_next):
    route = request.url.path
    if route in ("/metrics", "/health"):
        return await call_next(request)
    IN_FLIGHT.inc(); t0 = time.perf_counter()
    try:
        response = await call_next(request)
    finally:
        IN_FLIGHT.dec()
    dur = time.perf_counter() - t0
    ctx = trace.get_current_span().get_span_context()
    LATENCY.labels(route=route).observe(dur, exemplar={"trace_id": format(ctx.trace_id, "032x")} if ctx.is_valid else None)
    REQUESTS.labels(route=route, status=str(response.status_code)).inc()
    kv = {"method": request.method, "route": route, "status": response.status_code, "duration_ms": round(dur * 1000, 1)}
    kv.update(getattr(request.state, "log", {}))
    log("error" if response.status_code >= 500 else "info", "request", **kv)
    return response


@app.get("/metrics")
def metrics():
    return Response(generate_latest(REGISTRY), media_type=CONTENT_TYPE_LATEST)


@app.get("/health")
def health():
    return {"status": "ok", "version": VERSION, "search_transcripts": TRANSCRIPTS}


@app.get("/ask")
def ask(q: str, request: Request):
    word = q.lower().split()[-1] if q.strip() else ""
    try:
        conn = pool.get(timeout=POOL_WAIT)
    except queue.Empty:
        request.state.log = {"q": q, "error": "no free db connection"}
        return JSONResponse({"error": "busy, try again"}, status_code=503)
    POOL_USE.inc()
    try:
        rows = conn.execute("SELECT title FROM courses WHERE %s = ANY(topics) ORDER BY id LIMIT 3", (word,)).fetchall()
        if TRANSCRIPTS:   # version 1.1: also look inside lesson transcripts
            rows += conn.execute("SELECT c.title, count(*) FROM lessons l JOIN courses c ON c.id = l.course_id "
                                 "WHERE l.transcript ILIKE %s GROUP BY c.title ORDER BY 2 DESC LIMIT 3",
                                 (f"%{word}%",)).fetchall()
    except psycopg.Error as e:
        request.state.log = {"q": q, "error": str(e).strip().split("\n")[0][:120]}
        return JSONResponse({"error": "search failed"}, status_code=500)
    finally:
        pool.put(conn); POOL_USE.dec()
    titles = list(dict.fromkeys(r[0] for r in rows))
    request.state.log = {"q": q, "hits": len(titles)}
    if titles:
        return {"answer": f"Try the {titles[0]} course.", "courses": titles}
    return {"answer": "I could not find a course for that yet. Try asking about docker!", "courses": []}
