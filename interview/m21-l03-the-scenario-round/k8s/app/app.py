# allcsvideos catalog API (lab stand-in for the scenario round). Python standard library only.
# ONE worker, like a single sync gunicorn worker: requests are answered one at a time, in arrival order.
#   WORK_MS      CPU time each /courses request needs (default 20 ms)
#   CACHE_MB     memory warmed at start (really allocated and touched)
#   HEALTH_PORT  if set, /healthz is ALSO answered by its own small thread on this port (the fix). It answers 503
#                only if the worker has been stuck on ONE request for more than STUCK_S seconds (a real hang),
#                not when the worker is merely busy with a long queue.
import hashlib, json, os, socket, sys, threading, time
from http.server import BaseHTTPRequestHandler, HTTPServer, ThreadingHTTPServer

VERSION = os.environ.get("APP_VERSION", "1.0")
WORK_MS = float(os.environ.get("WORK_MS", "20"))
CACHE_MB = int(os.environ.get("CACHE_MB", "0"))
HEALTH_PORT = os.environ.get("HEALTH_PORT")
APP = os.environ.get("APP_NAME", "catalog")
STUCK_S = float(os.environ.get("STUCK_S", "10"))
busy_since = None
log = lambda m: print(f"{time.strftime('%H:%M:%S')} {APP} {m}", flush=True)

log(f"{VERSION} starting, warming cache: {CACHE_MB} MB")
cache = [bytearray(b"x" * (1024 * 1024)) for _ in range(CACHE_MB)]
COURSES = ["DSA", "System Design", "DevOps", "GenAI", "Spring Boot"]
served = 0

def work():
    t, h = time.thread_time(), b"allcs"
    while (time.thread_time() - t) * 1000 < WORK_MS:
        h = hashlib.sha256(h).digest()

class H(BaseHTTPRequestHandler):
    def _send(self, code, body):
        b = (json.dumps(body) + "\n").encode()
        try:
            self.send_response(code); self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
        except (BrokenPipeError, ConnectionResetError):
            pass                                      # the client gave up waiting
    def do_GET(self):
        global served, busy_since
        if self.path == "/healthz":
            if self.server.server_port != 8080 and busy_since and time.time() - busy_since > STUCK_S:
                return self._send(503, {"status": "stuck", "busy_s": round(time.time() - busy_since, 1)})
            return self._send(200, {"status": "ok"})
        if self.path in ("/courses", "/"):
            busy_since = time.time(); work(); served += 1; busy_since = None
            return self._send(200, {"version": VERSION, "pod": socket.gethostname(), "courses": COURSES})
        self._send(404, {"error": "not found"})
    def log_message(self, fmt, *args):
        pass                                          # per-request logs off; a summary every 10 s instead

class OneWorker(HTTPServer):
    request_queue_size = 128                          # like a gunicorn backlog: waiting connections queue here

def summary():
    last = 0
    while True:
        time.sleep(10); n = served; log(f"served {n - last} requests in the last 10 s"); last = n

threading.Thread(target=summary, daemon=True).start()
if HEALTH_PORT:
    threading.Thread(target=ThreadingHTTPServer(("", int(HEALTH_PORT)), H).serve_forever, daemon=True).start()
    log(f"health endpoint on its own thread, port {HEALTH_PORT}")
log("listening on :8080 (one worker)")
OneWorker(("", 8080), H).serve_forever()
