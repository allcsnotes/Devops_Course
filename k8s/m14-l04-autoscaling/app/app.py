"""allcsvideos API for the autoscaling lesson. Python standard library only.

  GET /recommend?user=U&n=N   course recommendations for a user: hashes the user's watch history N times
                              (default N=20000), so every request costs real CPU, like a busy API endpoint.
                              One worker computes at a time (like a single gunicorn worker); a request that waited
                              in the queue longer than MAX_WAIT seconds (default 1.5) gets 503 "busy" instead
  GET /readyz                 readiness: 200 "ready" once warm-up is over
  GET /healthz                liveness: 200 "alive"
STARTUP_SECONDS (default 2): warm-up before the port opens (a cold start: loading the catalog).
"""
import hashlib, os, signal, socket, sys, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

POD = socket.gethostname()
STARTUP = float(os.environ.get("STARTUP_SECONDS", "2"))
MAX_WAIT = float(os.environ.get("MAX_WAIT", "1.5"))
WORKER = threading.Semaphore(1)  # one request computes at a time; the rest wait in line
COURSES = ["DSA", "System Design", "DevOps", "Spring Boot", "GenAI"]


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def recommend(user, n):
    h = f"{user}:watched:DSA,DevOps".encode()
    for _ in range(n):                      # the CPU-heavy part
        h = hashlib.sha256(h).digest()
    i = h[0] % len(COURSES)
    return [COURSES[i], COURSES[(i + 1) % len(COURSES)]]


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, code, body, ctype="text/plain"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("X-Pod", POD)
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path == "/recommend":
            user = q.get("user", ["lukas"])[0]
            n = int(q.get("n", ["20000"])[0])
            t0 = time.time()
            with WORKER:
                if time.time() - t0 > MAX_WAIT:          # the user gave up long ago: don't burn CPU for nobody
                    return self.reply(503, "busy\n")
                recs = recommend(user, n)
            return self.reply(200, '{"user":"%s","recommended":["%s","%s"],"pod":"%s"}\n' % (user, recs[0], recs[1], POD), "application/json")
        if u.path == "/readyz":
            return self.reply(200, "ready\n")
        if u.path == "/healthz":
            return self.reply(200, "alive\n")
        self.reply(404, "not found\n")

    def log_message(self, *a):
        pass


signal.signal(signal.SIGTERM, lambda *_: (log("SIGTERM: shutting down"), sys.exit(0)))
log(f"allcsvideos API starting, warm-up {STARTUP:g} s")
time.sleep(STARTUP)
srv = ThreadingHTTPServer(("0.0.0.0", 8080), H)
srv.daemon_threads = True
log("listening on :8080")
srv.serve_forever()
