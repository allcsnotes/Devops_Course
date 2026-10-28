"""allcsvideos lab services for M16-L04 (logs). One image, two roles, chosen by SERVICE:
  web  the edge gateway: gives every request a request_id (or keeps the caller's X-Request-ID), forwards to the api
       with that header, and returns it to the browser as X-Request-ID / "reference" on errors
  api  the course catalog and checkout (in-memory data, lab build). Coupon LAUNCH2026 has no expiry date: a real bug,
       staged on purpose. About 1 in 1,000 checkouts gets a (simulated) payment gateway timeout.
Python 3.13 standard library only."""
import json, logging, os, random, secrets, time, urllib.error, urllib.request
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

from logsetup import setup, request_id

SERVICE = os.environ.get("SERVICE", "api")
API = os.environ.get("API_URL", "http://api:8080")
log = setup()

COURSES = {i: {"id": i, "title": t, "price": p} for i, (t, p) in enumerate([
    ("Linux from zero", 499), ("Docker in depth", 499), ("Kubernetes in production", 799),
    ("Terraform on AWS", 699), ("Observability", 599), ("System Design", 999)], start=101)}
COUPONS = {"WELCOME10": {"pct": 10, "expires": "2026-12-31"},
           "DIWALI25": {"pct": 25, "expires": "2026-11-05"},
           "LAUNCH2026": {"pct": 30, "expires": None}}          # created without an expiry date


def ev(level, msg, **kv):
    log.log(level, msg, extra={"fields": kv})


def price_for(course, code):
    if not code:
        return course["price"]
    c = COUPONS.get(code)
    if c is None:
        raise LookupError("unknown coupon")
    if datetime.fromisoformat(c["expires"]) < datetime.now():     # TypeError when expires is None
        raise LookupError("coupon expired")
    return round(course["price"] * (100 - c["pct"]) / 100)


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send(self, code, obj):
        b = (json.dumps(obj) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.send_header("X-Request-ID", request_id.get())
        self.end_headers()
        self.wfile.write(b)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}

    def handle_one(self, method):
        rid = self.headers.get("X-Request-ID", "")
        request_id.set(rid if len(rid) == 32 and all(c in "0123456789abcdef" for c in rid) else secrets.token_hex(16))
        t0 = time.perf_counter()
        path = self.path.split("?")[0]
        user = self.headers.get("X-User", "anonymous")
        try:
            code, obj, extra = (self.web if SERVICE == "web" else self.api)(method, path, user)
        except Exception:
            log.exception("unhandled error", extra={"fields": {"method": method, "path": path, "user": user}})
            code, obj, extra = 500, {"error": "something went wrong", "reference": request_id.get()}, {}
        ms = round((time.perf_counter() - t0) * 1000, 1)
        if path != "/healthz":
            lvl = logging.ERROR if code >= 500 else logging.WARNING if code == 404 or ms > 500 else logging.INFO
            ev(lvl, "request", method=method, path=path, status=code, duration_ms=ms, user=user, **extra)
        self.send(code, obj)

    def do_GET(self):
        self.handle_one("GET")

    def do_POST(self):
        self.handle_one("POST")

    # ---------- web: the gateway ----------
    def web(self, method, path, user):
        if path == "/healthz":
            return 200, {"ok": True}, {}
        if method == "POST" and path == "/api/login":
            b = self.body()
            log.debug("login body", extra={"fields": {"body": b}})
            ev(logging.INFO, "login attempt", email=b.get("email"), password=b.get("password"))   # the leak, if REDACT=0
            return 200, {"token": "demo-token-" + secrets.token_hex(4)}, {}
        data = self.body() if method == "POST" else None
        req = urllib.request.Request(API + path.removeprefix("/api"), method=method,
                                     data=json.dumps(data).encode() if data is not None else None,
                                     headers={"X-Request-ID": request_id.get(), "X-User": user, "Content-Type": "application/json"})
        t1 = time.perf_counter()
        try:
            with urllib.request.urlopen(req, timeout=3) as r:
                code, obj = r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            code, obj = e.code, json.loads(e.read() or b"{}")
        upstream_ms = round((time.perf_counter() - t1) * 1000, 1)
        if code >= 500:
            obj = {"error": "something went wrong", "reference": request_id.get()}
        return code, obj, {"upstream_ms": upstream_ms}

    # ---------- api: catalog and checkout ----------
    def api(self, method, path, user):
        if path == "/healthz":
            return 200, {"ok": True}, {}
        if path == "/courses":
            log.debug("cache hit", extra={"fields": {"key": "courses:all"}})
            return 200, {"courses": list(COURSES.values())}, {}
        if path.startswith("/courses/"):
            c = COURSES.get(int(path.rsplit("/", 1)[1]) if path.rsplit("/", 1)[1].isdigit() else -1)
            return (200, c, {}) if c else (404, {"error": "no such course"}, {})
        if method == "POST" and path == "/checkout":
            b = self.body()
            course = COURSES.get(b.get("course_id"))
            if not course:
                return 404, {"error": "no such course"}, {}
            amount = price_for(course, b.get("coupon"))
            if random.random() < 0.001:
                ev(logging.WARNING, "payment gateway slow, giving up", gateway="demo-pay", waited_ms=2000)
                return 504, {"error": "payment gateway timeout"}, {"course_id": course["id"]}
            ev(logging.INFO, "order placed", course_id=course["id"], amount_inr=amount, coupon=b.get("coupon"))
            return 200, {"order": secrets.token_hex(6), "amount_inr": amount}, {"course_id": course["id"]}
        return 404, {"error": "not found"}, {}

    def log_message(self, *a):
        pass


ev(logging.INFO, "listening", port=8080, pid=os.getpid())
srv = ThreadingHTTPServer(("0.0.0.0", 8080), H)
srv.daemon_threads = True
srv.serve_forever()
