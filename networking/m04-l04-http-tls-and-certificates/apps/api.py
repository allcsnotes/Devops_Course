# API stand-in for this lab (the real allcsvideos API is the Spring Boot app). Port 8080.
# GET /api/health · GET /api/whoami (echoes what the proxy passed on) · POST /api/login · GET /api/me
import json, os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

SESSION = "lab-session-7f3a9c"   # FAKE session id, lab only

class H(BaseHTTPRequestHandler):
    def send(self, code, body, extra=()):
        data = (json.dumps(body) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        for k, v in extra:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/api/health":
            return self.send(200, {"status": "ok", "service": "api", "host": os.uname().nodename})
        if self.path == "/api/whoami":
            h = self.headers
            return self.send(200, {"peer": self.client_address[0], "host": h.get("Host"),
                                   "x_forwarded_for": h.get("X-Forwarded-For"),
                                   "x_forwarded_proto": h.get("X-Forwarded-Proto")})
        if self.path == "/api/me":
            if f"session={SESSION}" in (self.headers.get("Cookie") or ""):
                return self.send(200, {"user": "lukas", "courses": 3})
            return self.send(401, {"error": "not logged in"})
        self.send(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/api/login":
            n = int(self.headers.get("Content-Length") or 0)
            form = parse_qs(self.rfile.read(n).decode())
            if form.get("user") == ["lukas"] and form.get("password") == ["demo-password-123"]:
                return self.send(200, {"user": "lukas"}, [("Set-Cookie", f"session={SESSION}; Path=/; HttpOnly")])
            return self.send(401, {"error": "bad login"})
        self.send(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        print("%s %s" % (self.client_address[0], fmt % args), flush=True)

ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
