"""allcsvideos API stand-in for M06-L03 (a tiny real HTTP service, Python standard library only).

Config comes from environment variables (12-factor):
  PORT       port to listen on            (image default 8080)
  LOG_LEVEL  DEBUG | INFO | WARNING        (image default INFO)
  DB_URL     database URL (FAKE in this lesson; the app only prints it, masked)
Logs go to stdout (INFO, DEBUG) and stderr (WARNING, ERROR), never to files.
SIGTERM (and Ctrl-C) -> graceful shutdown, exit code 0.
--no-sigterm-handler   staged variant: no SIGTERM handler is installed (like most code nobody wrote one for).
"""
import json, os, re, signal, sys, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

LEVELS = {"DEBUG": 10, "INFO": 20, "WARNING": 30, "ERROR": 40}
LEVEL = LEVELS.get(os.environ.get("LOG_LEVEL", "INFO").upper(), 20)
VERSION = "1.0"
COURSES = [{"id": 1, "title": "DSA"}, {"id": 2, "title": "System Design"}, {"id": 3, "title": "DevOps"}]


def log(level, msg):
    if LEVELS[level] < LEVEL:
        return
    out = sys.stderr if LEVELS[level] >= 30 else sys.stdout
    print(f"{level:<7} {msg}", file=out, flush=True)


def mask(url):
    return re.sub(r"://([^:/@]+):([^@]+)@", r"://\1:****@", url) if url else "(not set)"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # silence the default access log; we log ourselves
        pass

    def send_json(self, code, body):
        data = (json.dumps(body) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        t0 = time.perf_counter()
        log("DEBUG", f"request from {self.client_address[0]} user-agent={self.headers.get('User-Agent')}")
        if self.path == "/health":
            code, body = 200, {"status": "ok", "version": VERSION}
        elif self.path == "/courses":
            code, body = 200, COURSES
        else:
            code, body = 404, {"error": "not found"}
        self.send_json(code, body)
        ms = (time.perf_counter() - t0) * 1000
        log("INFO" if code < 400 else "WARNING", f"GET {self.path} {code} {ms:.1f}ms")


def main():
    try:
        port = int(os.environ.get("PORT", "8080"))
    except ValueError:
        log("ERROR", f"PORT must be a number, got {os.environ.get('PORT')!r}")
        sys.exit(1)
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)

    def graceful(signum, frame):
        log("INFO", f"{signal.Signals(signum).name} received: finishing in-flight requests")
        threading.Thread(target=server.shutdown).start()

    if "--no-sigterm-handler" in sys.argv:
        log("WARNING", "no SIGTERM handler installed (staged variant)")
    else:
        signal.signal(signal.SIGTERM, graceful)
    signal.signal(signal.SIGINT, graceful)

    log("INFO", f"allcsvideos api {VERSION} starting, pid {os.getpid()}")
    log("INFO", f"config: log_level={logging_name()} db={mask(os.environ.get('DB_URL'))}")
    log("DEBUG", "config read from environment variables: PORT, LOG_LEVEL, DB_URL")
    log("INFO", f"listening on 0.0.0.0:{port}")
    server.serve_forever()
    server.server_close()
    log("INFO", "shutdown complete, bye")


def logging_name():
    return {v: k for k, v in LEVELS.items()}[LEVEL]


if __name__ == "__main__":
    main()
