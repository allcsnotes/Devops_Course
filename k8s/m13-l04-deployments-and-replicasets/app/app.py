"""allcsvideos storefront. Python standard library only.

Like a real web app it needs a few seconds to start (loading templates, warming caches) before it listens:
WARMUP seconds (default 4). Then it serves on port 8080:
  GET /               the storefront page; every response carries X-App-Version and X-Pod
  GET /healthz/ready  200 "ready" when it can serve, 503 otherwise
On SIGTERM it keeps serving for DRAIN seconds (default 3), then exits 0 (graceful shutdown, as in M13-L03).

Version 3.0.0 is a bad build, staged on purpose: it starts, but it can't load its catalog config,
so /healthz/ready says 503 and / answers 500.
"""
import os, signal, socket, sys, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

VERSION = os.environ.get("APP_VERSION", "0.0.0")
POD = socket.gethostname()
WARMUP = float(os.environ.get("WARMUP", "4"))
DRAIN = float(os.environ.get("DRAIN", "3"))
BAD = VERSION.startswith("3.")


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, code, body):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8" if self.path == "/" else "text/plain")
        self.send_header("Content-Length", str(len(b)))
        self.send_header("X-App-Version", VERSION)
        self.send_header("X-Pod", POD)
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/healthz/ready":
            return self.reply(503, "catalog config missing\n") if BAD else self.reply(200, "ready\n")
        if self.path == "/":
            if BAD:
                return self.reply(500, "Internal Server Error\n")
            return self.reply(200, f"<!doctype html><title>allcsvideos</title><h1>allcsvideos storefront</h1>"
                                   f"<p>version {VERSION} · served by {POD}</p>\n")
        self.reply(404, "not found\n")

    def log_message(self, *a):
        pass


log(f"allcsvideos storefront {VERSION} starting (warm-up {WARMUP:g} s)")
time.sleep(WARMUP)
srv = ThreadingHTTPServer(("0.0.0.0", 8080), H)
srv.daemon_threads = True
if BAD:
    log("ERROR catalog config missing: CATALOG_URL is not set")
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
sys.exit(0)
