#!/usr/bin/env python3
# Course Copilot stand-in for this lesson: answers GET /health on port 8000.
# Like many dev servers (uvicorn, flask run), its default host is 127.0.0.1: reachable only from the machine itself.
import argparse, json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        ok = self.path == "/health"
        body = json.dumps({"status": "ok"} if ok else {"error": "not found"}).encode() + b"\n"
        self.send_response(200 if ok else 404)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass

p = argparse.ArgumentParser()
p.add_argument("--host", default="127.0.0.1")
p.add_argument("--port", type=int, default=8000)
a = p.parse_args()
ThreadingHTTPServer((a.host, a.port), H).serve_forever()
