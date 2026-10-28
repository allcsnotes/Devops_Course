# allcsvideos catalog API (a stand-in for the Spring Boot API). Standard library only.
# Needs DATABASE_URL; refuses to start without it, the way a real service with a missing setting should.
import json, os, socket, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = os.environ.get("APP_VERSION", "2.4.0")
DB = os.environ.get("DATABASE_URL")
if not DB:
    print("FATAL: DATABASE_URL is not set. Refusing to start.", file=sys.stderr, flush=True)
    sys.exit(1)
print(f"catalog-api {VERSION} starting, database {DB.split('@')[-1]}", flush=True)
COURSES = ["DSA", "System Design", "DevOps", "GenAI", "Spring Boot"]

class H(BaseHTTPRequestHandler):
    def _send(self, code, body):
        b = json.dumps(body).encode()
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

port = int(os.environ.get("PORT", "8080"))
print(f"listening on :{port}", flush=True)
ThreadingHTTPServer(("", port), H).serve_forever()
