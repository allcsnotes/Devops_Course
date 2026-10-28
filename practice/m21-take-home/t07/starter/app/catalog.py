"""catalog: the allcsvideos course-list API stand-in for the observability take-home (no real database).

GET /api/courses  the course list (fails with 503 for a share of requests: ERROR_RATE, default 0)
GET /healthz      liveness
Not instrumented yet: that is the task.
"""
import json
import os
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ERROR_RATE = float(os.environ.get("ERROR_RATE", "0"))
COURSES = [{"id": "dsa"}, {"id": "devops"}, {"id": "genai"}]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            return self.reply(200, {"status": "ok"})
        if self.path == "/api/courses":
            time.sleep(random.uniform(0.005, 0.040))   # pretend database work
            if random.random() < ERROR_RATE:
                return self.reply(503, {"error": "database unavailable"})
            return self.reply(200, COURSES)
        return self.reply(404, {"error": "not found"})

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
