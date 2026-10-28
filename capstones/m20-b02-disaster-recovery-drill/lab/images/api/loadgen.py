"""Simulated students for M20-B02 (from the M17-L04 load generator): a small, steady open-model load.

RATE requests a second to the storefront: 4 in 5 browse the course list, 1 in 5 enrolls (a write).
They are the users, so they live OUTSIDE the production environment and survive the staged disaster.
  /data/acks.csv       every enrollment the site confirmed (time, id, student): what students were told was saved
  /data/requests.csv   every request (time, route, result, ms): the drill timeline is drawn from this file
  :9100/metrics        http_requests_total{route, code}, http_request_duration_seconds{route}, http_requests_in_flight
"""
import json, os, random, threading, time, urllib.request, urllib.error
from datetime import datetime, timezone, timedelta
from prometheus_client import Counter, Gauge, Histogram, start_http_server

RATE = float(os.environ.get("RATE", "10"))
URL = os.environ.get("TARGET", "http://10.0.202.30:30080")
TIMEOUT = float(os.environ.get("TIMEOUT", "3"))
IST = timezone.utc   # the lab runs in UTC (ops box, database, bucket)

REQS = Counter("http_requests_total", "requests sent by the simulated students", ["route", "code"])
LAT = Histogram("http_request_duration_seconds", "client-side request duration", ["route"],
                buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2, 3))
IN_FLIGHT = Gauge("http_requests_in_flight", "requests waiting for an answer")
for r in ("/api/courses", "/api/enroll"):
    for c in ("200", "201", "502", "503", "error"):
        REQS.labels(r, c)                       # every series exists at 0 from the start
acks = open("/data/acks.csv", "a", buffering=1)
reqs = open("/data/requests.csv", "a", buffering=1)
alock = threading.Lock()


def now():
    return datetime.now(IST).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]


def one(n):
    enroll = n % 5 == 0
    route = "/api/enroll" if enroll else "/api/courses"
    student = f"student{random.randint(1, 999999):06d}@example.com"
    if enroll:
        body = json.dumps({"student": student, "course_id": random.randint(1, 40)}).encode()
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
    dt = time.perf_counter() - t0
    LAT.labels(route).observe(dt); REQS.labels(route, code).inc(); IN_FLIGHT.dec()
    with alock:
        reqs.write(f"{now()},{route},{code},{dt * 1000:.0f}\n")
        if enroll and code == "201":
            acks.write(f"{now()},{json.loads(data)['enrollment']},{student}\n")


start_http_server(9100)
print(f"students: {RATE:g} requests/s to {URL}, timeout {TIMEOUT:g}s", flush=True)
n, t_next = 0, time.perf_counter()
while True:
    threading.Thread(target=one, args=(n,), daemon=True).start()
    n += 1; t_next += 1 / RATE
    time.sleep(max(0, t_next - time.perf_counter()))
