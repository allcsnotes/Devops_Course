"""Course Copilot (no AI model), M16-L02 lab build: now with Prometheus metrics.

It answers "which course covers X?" from a course index file, and reports its health.
Config comes from environment variables:
  APP_VERSION    shown by /health            (image default: set at build time)
  COURSE_INDEX   path to the course index    (image default /app/data/courses.json)
  MODEL_DELAY_MS lab only: mean of a random delay that plays the model call (default 0)
  FAULT_RATE     lab only: share of /ask answers that fail with 500, staged on purpose (default 0)
  TRACK_USERS    lab only, THE MISTAKE: put user_id on the latency histogram (default off)
"""
import json
import os
import random
import time

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

app = FastAPI(title="Course Copilot")
VERSION = os.environ.get("APP_VERSION", "dev")
INDEX = os.environ.get("COURSE_INDEX", "data/courses.json")
DELAY = float(os.environ.get("MODEL_DELAY_MS", "0")) / 1000
FAULTS = float(os.environ.get("FAULT_RATE", "0"))
TRACK_USERS = os.environ.get("TRACK_USERS") == "1"

REQUESTS = Counter("copilot_requests", "Requests handled.", ["route", "code"])
IN_FLIGHT = Gauge("copilot_requests_in_flight", "Requests being handled right now.")
COURSES = Gauge("copilot_courses_indexed", "Courses in the loaded index.")
LATENCY = Histogram("copilot_request_duration_seconds", "Time to answer a request.",
                    ["route", "user_id"] if TRACK_USERS else ["route"],
                    buckets=[0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5])


@app.middleware("http")
async def measure(request: Request, call_next):
    route = request.url.path
    if route == "/metrics":
        return await call_next(request)
    IN_FLIGHT.inc()
    start = time.perf_counter()
    try:
        response = await call_next(request)
    finally:
        IN_FLIGHT.dec()
    labels = {"route": route}
    if TRACK_USERS:
        labels["user_id"] = request.query_params.get("user", "anonymous")
    LATENCY.labels(**labels).observe(time.perf_counter() - start)
    REQUESTS.labels(route=route, code=str(response.status_code)).inc()
    return response


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


def load_index():
    with open(INDEX) as f:
        courses = json.load(f)
    COURSES.set(len(courses))
    return courses


@app.get("/health")
def health(response: Response):
    try:
        courses = load_index()
    except OSError:
        response.status_code = 503
        return {"status": "degraded", "error": "course index not found"}
    return {"status": "ok", "version": VERSION, "courses": len(courses)}


@app.get("/ask")
def ask(q: str, response: Response):
    if DELAY:
        time.sleep(min(random.expovariate(1 / DELAY), 3))   # lab: plays the model call
    if random.random() < FAULTS:                               # lab: a staged failure
        response.status_code = 500
        return {"error": "model backend timed out (staged)"}
    words = q.lower().split()
    for c in load_index():
        if any(w in c["topics"] for w in words):
            return {"answer": f"Try the {c['title']} course."}
    return {"answer": "Hi from Course Copilot! I could not find a course for that yet. Try asking about docker!"}
