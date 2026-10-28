#!/usr/bin/env python3
# allcsvideos API stand-in for the Linux lessons: answers /health and /courses on port 8080.
# Staged bug: GET /reindex starts a loop that never ends. It burns one CPU and blocks every other request.
from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/reindex':
            while True:          # the staged bug
                pass
        body = b'ok\n' if self.path == '/health' else b'{"courses": 3}\n'
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

print('allcsvideos-api: listening on port 8080', flush=True)
HTTPServer(('', 8080), Handler).serve_forever()
