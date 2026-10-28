#!/usr/bin/env python3
# STAND-INS for M03-L04, not the real services: the allcsvideos API (role "api", port 8080) and Course Copilot
# (role "copilot", port 8000). Each runs in its own python:3.13.16-slim container on the lab network lab-net.
# Fixed, realistic response delays, so timings are repeatable. Staging flags (created with docker exec, said on screen):
#   /tmp/redis-down     API /health reports Redis down: HTTP 200, {"status": "degraded", ...}
#   /tmp/model-missing  Copilot /health answers HTTP 503, {"status": "down", "reason": "model not loaded"}
#   GET /slow           (both) answers only after 60 s, for the timeout demos
import json, os, sys, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

ROLE, PORT = sys.argv[1], int(sys.argv[2])
COURSES = [{"slug": s, "title": t} for s, t in [("devops", "DevOps"), ("dsa", "DSA"), ("system-design", "System Design"),
                                                 ("spring-boot", "Spring Boot"), ("genai", "GenAI")]]


class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        sys.stderr.write("%s %s\n" % (self.log_date_time_string(), fmt % a))

    def reply(self, code, obj):
        b = (json.dumps(obj) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/slow":
            time.sleep(60)
            return self.reply(200, {"status": "ok"})
        if ROLE == "api" and self.path == "/health":
            time.sleep(0.3)
            if os.path.exists("/tmp/redis-down"):
                return self.reply(200, {"status": "degraded", "checks": {"db": {"status": "ok"}, "redis": {"status": "down"}}})
            return self.reply(200, {"status": "ok", "checks": {"db": {"status": "ok"}, "redis": {"status": "ok"}}})
        if ROLE == "api" and self.path == "/courses":
            time.sleep(0.6)
            return self.reply(200, COURSES)
        if ROLE == "copilot" and self.path == "/health":
            time.sleep(0.9)
            if os.path.exists("/tmp/model-missing"):
                return self.reply(503, {"status": "down", "reason": "model not loaded"})
            return self.reply(200, {"status": "ok", "model": "loaded"})
        self.reply(404, {"error": "not found"})


ThreadingHTTPServer(("", PORT), H).serve_forever()
