"""allcsvideos API stand-in (from M07-L02; Python standard library only, a real HTTP service).
Paths: /health (200 when the service is up), /whoami (which container and version answered).
"""
import json, os, signal, socket, sys
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

VERSION = "1.4.0"
HOST = socket.gethostname()


def log(msg):
    print(msg, flush=True)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send_json(self, code, body):
        data = (json.dumps(body) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            code, body = 200, {"status": "ok"}
        elif self.path == "/whoami":
            code, body = 200, {"api": HOST, "version": VERSION}
        else:
            code, body = 404, {"error": "not found"}
        self.send_json(code, body)
        log(f"GET {self.path} {code}")


def main():
    signal.signal(signal.SIGTERM, lambda *a: sys.exit(0))  # docker stop: exit cleanly
    port = int(os.environ.get("PORT", "8080"))
    log(f"allcsvideos api {VERSION} on {HOST}, listening on 0.0.0.0:{port}")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
