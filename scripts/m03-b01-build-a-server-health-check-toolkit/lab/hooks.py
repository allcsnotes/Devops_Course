#!/usr/bin/env python3
# hooks.py: a STAND-IN for a team chat incoming webhook (like the ones Slack or Google Chat give you).
# It accepts JSON on POST and prints each message it receives, so we can watch alerts arrive. Never a real external service.
import json
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        msg = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        print(f"{time.strftime('%H:%M:%S')}  POST {self.path}  {msg['host']}: {msg['from']} -> {msg['to']}", flush=True)
        for p in msg["problems"] or ["all checks OK again"]:
            print(f"          {p}", flush=True)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok\n")


print("hooks: listening on port 9000", flush=True)
ThreadingHTTPServer(("", 9000), H).serve_forever()
