"""catalog: the allcsvideos course-list API stand-in for the observability take-home (no real database).

GET /api/courses  the course list (fails with 503 for a share of requests: ERROR_RATE, default 0)
GET /healthz      liveness
GET /metrics      Prometheus metrics: http_requests_total, http_request_duration_seconds, http_requests_in_flight
"""
import json
import os
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

ERROR_RATE = float(os.environ.get("ERROR_RATE", "0"))
COURSES = [{"id": "dsa"}, {"id": "devops"}, {"id": "genai"}]
ROUTES = {"/api/courses", "/healthz"}          # anything else is labelled "other": bounded cardinality

REQUESTS = Counter("http_requests_total", "HTTP requests handled.", ["route", "status"])
LATENCY = Histogram("http_request_duration_seconds", "HTTP request duration.", ["route"],
                    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5))
IN_FLIGHT = Gauge("http_requests_in_flight", "HTTP requests being handled now.")

# pre-create the label sets we alert on, so ratios exist (as 0) before the first error
for code in ("200", "404", "503"):
    REQUESTS.labels("/api/courses", code)
LATENCY.labels("/api/courses")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            data = generate_latest()
            self.send_response(200)
            self.send_header("Content-Type", CONTENT_TYPE_LATEST)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        route = self.path if self.path in ROUTES else "other"
        start = time.perf_counter()
        IN_FLIGHT.inc()
        try:
            status, body = self.handle_route()
        finally:
            IN_FLIGHT.dec()
        LATENCY.labels(route).observe(time.perf_counter() - start)
        REQUESTS.labels(route, str(status)).inc()
        self.reply(status, body)

    def handle_route(self):
        if self.path == "/healthz":
            return 200, {"status": "ok"}
        if self.path == "/api/courses":
            time.sleep(random.uniform(0.005, 0.040))   # pretend database work
            if random.random() < ERROR_RATE:
                return 503, {"error": "database unavailable"}
            return 200, COURSES
        return 404, {"error": "not found"}

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            pass

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
