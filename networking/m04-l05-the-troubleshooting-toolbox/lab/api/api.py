# allcsvideos API stand-in: answers /api/health and /api/courses on port 8080.
# Each request first sleeps for the number of seconds in /etc/api-delay (0 = no delay), to stage a slow backend.
import json, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

COURSES = [{"id": "dsa", "title": "DSA"}, {"id": "devops", "title": "DevOps"}]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        t0 = time.time()
        try:
            time.sleep(float(open("/etc/api-delay").read() or 0))
        except FileNotFoundError:
            pass
        if self.path == "/api/health":
            code, body = 200, {"status": "ok"}
        elif self.path == "/api/courses":
            code, body = 200, COURSES
        else:
            code, body = 404, {"error": "not found"}
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        print(f'{time.strftime("%H:%M:%S")} GET {self.path} {code} {time.time() - t0:.3f}s', flush=True)

    def log_message(self, *args):
        pass

ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
