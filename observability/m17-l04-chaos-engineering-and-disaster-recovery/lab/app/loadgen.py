"""Simulated students for M17-L04: a small, steady load generator (open model, like k6's constant-arrival-rate).

RATE requests a second through the load balancer: 9 in 10 read the course list, 1 in 10 enrolls (a write).
It measures from the user's side and exposes the shared metric names on :9100, job "students":
  http_requests_total{route, code}       code = HTTP status, or "error" when no answer came back at all
  http_request_duration_seconds{route}   histogram, client side
  http_requests_in_flight
Every enrollment the API confirmed is appended to /data/acks.csv (time, id): what the students were told was saved.
"""
import json, os, random, threading, time, urllib.request, urllib.error
from datetime import datetime, timezone, timedelta
from prometheus_client import Counter, Gauge, Histogram, start_http_server

RATE = float(os.environ.get("RATE", "20"))
URL = os.environ.get("TARGET", "http://lb")
TIMEOUT = float(os.environ.get("TIMEOUT", "3"))
IST = timezone(timedelta(hours=5, minutes=30))

REQS = Counter("http_requests_total", "requests sent by the simulated students", ["route", "code"])
LAT = Histogram("http_request_duration_seconds", "client-side request duration", ["route"],
                buckets=(.005, .01, .025, .05, .1, .15, .2, .25, .3, .4, .5, .75, 1, 1.5, 2, 3))
IN_FLIGHT = Gauge("http_requests_in_flight", "requests waiting for an answer")
acks = open("/data/acks.csv", "a", buffering=1)
alock = threading.Lock()


def one(n):
    enroll = n % 10 == 0
    route = "/api/enroll" if enroll else "/api/courses"
    if enroll:
        body = json.dumps({"student": f"student{random.randint(1, 999999):06d}@example.com", "course_id": random.randint(1, 40)}).encode()
        req = urllib.request.Request(URL + route, data=body, method="POST", headers={"Content-Type": "application/json"})
    else:
        req = urllib.request.Request(URL + route)
    t0 = time.perf_counter(); IN_FLIGHT.inc(); code = "error"; data = b""
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            code = str(r.status); data = r.read()
    except urllib.error.HTTPError as e:
        code = str(e.code)
    except Exception:
        code = "error"
    LAT.labels(route).observe(time.perf_counter() - t0); REQS.labels(route, code).inc(); IN_FLIGHT.dec()
    if enroll and code == "201":
        eid = json.loads(data)["enrollment"]
        with alock:
            acks.write(f"{datetime.now(IST).strftime('%H:%M:%S.%f')[:-3]},{eid}\n")


start_http_server(9100)
print(f"students: {RATE:g} requests/s to {URL}, timeout {TIMEOUT:g}s", flush=True)
n, t_next = 0, time.perf_counter()
while True:
    threading.Thread(target=one, args=(n,), daemon=True).start()
    n += 1; t_next += 1 / RATE
    time.sleep(max(0, t_next - time.perf_counter()))
