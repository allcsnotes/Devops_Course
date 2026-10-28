"""allcsvideos API. Python standard library only.

Serves on port 8080 (HTTP/1.1, keep-alive allowed, so one connection can carry several requests):
  GET /               {"service":"api","version":"...","pod":"..."}
  GET /whoami         the pod name, one line
  GET /healthz/ready  200 "ready", or 503 "draining" while the file /tmp/drain exists
It needs WARMUP seconds (default 2) to start, and on SIGTERM keeps serving for DRAIN seconds (default 3), then exits 0.
"""
import json, os, signal, socket, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

VERSION = os.environ.get("APP_VERSION", "0.0.0")
POD = socket.gethostname()
WARMUP = float(os.environ.get("WARMUP", "2"))
DRAIN = float(os.environ.get("DRAIN", "3"))


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, code, body, ctype="text/plain"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("X-Pod", POD)
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/healthz/ready":
            return self.reply(503, "draining\n") if os.path.exists("/tmp/drain") else self.reply(200, "ready\n")
        if self.path == "/whoami":
            return self.reply(200, POD + "\n")
        if self.path == "/":
            return self.reply(200, json.dumps({"service": "api", "version": VERSION, "pod": POD}) + "\n", "application/json")
        self.reply(404, "not found\n")

    def log_message(self, *a):
        pass


log(f"allcsvideos api {VERSION} starting")
time.sleep(WARMUP)
srv = ThreadingHTTPServer(("0.0.0.0", 8080), H)
srv.daemon_threads = True
log(f"listening on :8080, version {VERSION}")


def on_term(*_):
    log(f"SIGTERM: draining for {DRAIN:g} s")

    def stop():
        time.sleep(DRAIN)
        log("shutdown complete")
        srv.shutdown()
    threading.Thread(target=stop, daemon=True).start()


signal.signal(signal.SIGTERM, on_term)
srv.serve_forever()
