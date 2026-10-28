"""Simulated students for the game day (fake users only). Open model, like k6's constant-arrival-rate:
RATE requests a second through the load balancer, no matter how slow the answers are.
9 in 10 open the course list, 1 in 10 asks Course Copilot. 3 second client timeout.
Measures from the user's side with the shared metric names on :9100 (job "students"):
  http_requests_total{route, code}   code = HTTP status, or "error" when no answer came back at all
  http_request_duration_seconds{route}
Every request is also appended to /runs/students.csv (epoch,route,code,ms): the timeline is built from it."""
import os, random, threading, time, urllib.error, urllib.request
from prometheus_client import Counter, Histogram, start_http_server

RATE = float(os.environ.get("RATE", "20"))
URL = os.environ.get("TARGET", "http://lb")
REQS = Counter("http_requests_total", "requests sent by the simulated students", ["route", "code"])
LAT = Histogram("http_request_duration_seconds", "client-side request duration", ["route"],
                buckets=(.01, .025, .05, .1, .15, .2, .25, .3, .5, .75, 1, 1.5, 2, 3))
for r in ("/api/courses", "/api/ask"):
    for c in ("200", "500", "502", "503", "504", "error"):
        REQS.labels(r, c)
Q = ["docker for beginners", "kubernetes", "learn linux", "terraform modules", "system design", "spring boot", "devops roadmap"]
out = open("/runs/students.csv", "a", buffering=1)
olock = threading.Lock()


def one(n):
    ask = n % 10 == 5
    route = "/api/ask" if ask else "/api/courses"
    url = URL + (f"/api/ask?q={urllib.request.quote(random.choice(Q))}" if ask else "/api/courses")
    t0, start, code = time.perf_counter(), time.time(), "error"
    try:
        with urllib.request.urlopen(url, timeout=3) as r:
            r.read(); code = str(r.status)
    except urllib.error.HTTPError as e:
        code = str(e.code)
    except Exception:
        code = "error"
    ms = (time.perf_counter() - t0) * 1000
    LAT.labels(route).observe(ms / 1000); REQS.labels(route, code).inc()
    with olock:
        out.write(f"{start:.3f},{route},{code},{ms:.1f}\n")


start_http_server(9100)
print(f"students: {RATE:g} requests/s to {URL}, timeout 3s", flush=True)
n, t_next = 0, time.perf_counter()
while True:
    threading.Thread(target=one, args=(n,), daemon=True).start()
    n += 1; t_next += 1 / RATE
    time.sleep(max(0, t_next - time.perf_counter()))
