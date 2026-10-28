# allcsvideos catalog API (lab stand-in, Kubernetes scenarios). Python standard library only.
# Settings come from a ConfigMap: PAGE_SIZE must be an integer; CACHE_MB is the size of the warm-up cache in memory.
import json, os, socket, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = os.environ.get("APP_VERSION", "1.0")
try:
    PAGE_SIZE = int(os.environ.get("PAGE_SIZE", "20"))
except ValueError:
    print(f"FATAL config: PAGE_SIZE={os.environ['PAGE_SIZE']!r} is not an integer", file=sys.stderr, flush=True)
    sys.exit(1)
CACHE_MB = int(os.environ.get("CACHE_MB", "8"))
print(f"catalog {VERSION} warming cache: {CACHE_MB} MB", flush=True)
cache = []
for i in range(CACHE_MB):
    cache.append(bytearray(1024 * 1024))           # really allocated and touched
    if (i + 1) % 16 == 0:
        print(f"cache {i + 1} MB", flush=True)
COURSES = ["DSA", "System Design", "DevOps", "GenAI", "Spring Boot"][:PAGE_SIZE]

class H(BaseHTTPRequestHandler):
    def _send(self, code, body):
        b = (json.dumps(body) + "\n").encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path == "/healthz":
            return self._send(200, {"status": "ok"})
        if self.path in ("/courses", "/"):
            return self._send(200, {"version": VERSION, "pod": socket.gethostname(), "courses": COURSES})
        self._send(404, {"error": "not found"})
    def log_message(self, fmt, *args):
        print(f"{time.strftime('%H:%M:%S')} {self.command} {self.path} {args[1]}", flush=True)

print("listening on :8080", flush=True)
ThreadingHTTPServer(("", 8080), H).serve_forever()
