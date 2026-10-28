#!/usr/bin/env python3
# allcsvideos API STAND-IN for this build (not the real Spring Boot API): port 8080, GET /health -> {"status": "ok"}.
import json
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        code, obj = (200, {"status": "ok"}) if self.path == "/health" else (404, {"error": "not found"})
        b = (json.dumps(obj) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)


ThreadingHTTPServer(("", 8080), H).serve_forever()
