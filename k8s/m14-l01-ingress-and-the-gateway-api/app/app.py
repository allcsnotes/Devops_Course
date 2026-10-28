"""allcsvideos demo service. Python standard library only.

One image, three services: SERVICE=storefront | api | copilot, APP_VERSION=1.0.0 ...
Serves on port 8080. Every path answers, so routing demos show what the backend received:
  GET <any path>      {"service":"...","version":"...","path":"...","pod":"..."}
  GET /healthz        200 "ok"
"""
import json, os, socket, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

SERVICE = os.environ.get("SERVICE", "demo")
VERSION = os.environ.get("APP_VERSION", "0.0.0")
POD = socket.gethostname()


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path == "/healthz":
            body, ctype = "ok\n", "text/plain"
        else:
            body = json.dumps({"service": SERVICE, "version": VERSION, "path": self.path, "pod": POD}) + "\n"
            ctype = "application/json"
        b = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):
        pass


print(time.strftime("%H:%M:%S"), f"allcsvideos {SERVICE} {VERSION} listening on :8080", flush=True)
srv = ThreadingHTTPServer(("0.0.0.0", 8080), H)
srv.daemon_threads = True
srv.serve_forever()
