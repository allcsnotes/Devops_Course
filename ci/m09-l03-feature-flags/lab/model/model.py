"""LAB STAND-IN for the AI model service that Course Copilot calls (no real model).

POST /answer  {"q": "..."}  -> {"answer": "..."} after 150-350 ms (a model is slow-ish)
POST /mode    body ok|broken -> staged failure switch for the lesson. In "broken" mode half the requests hang for
              3 s (Copilot gives up after 2 s) and the other half fail at once with HTTP 503.
"""
import json
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODE = {"now": "ok"}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        data = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.path == "/mode":
            MODE["now"] = data.decode().strip() or "ok"
            return self.reply(200, {"mode": MODE["now"]})
        q = json.loads(data or b"{}").get("q", "")
        if MODE["now"] == "broken":
            if random.random() < 0.5:
                time.sleep(3)
            else:
                return self.reply(503, {"error": "model overloaded"})
        time.sleep(random.uniform(0.15, 0.35))
        self.reply(200, {"answer": f"(model) For '{q}', start with module 6 of the DevOps course."})


ThreadingHTTPServer(("0.0.0.0", 9000), H).serve_forever()
