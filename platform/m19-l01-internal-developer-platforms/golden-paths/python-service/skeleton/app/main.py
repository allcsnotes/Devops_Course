"""${{ values.name }}: ${{ values.description }} (made from the python-service golden path)."""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVICE = "${{ values.name }}"


def handle(path):
    """Return (status, body) for a GET request."""
    if path == "/healthz":
        return 200, {"status": "ok"}
    if path == "/":
        return 200, {"service": SERVICE, "version": os.environ.get("VERSION", "dev")}
    return 404, {"error": "not found"}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        status, body = handle(self.path)
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
