"""allcsvideos API. Python standard library only.

Reads its settings from outside the image, the twelve-factor way:
  environment  APP_ENV, LOG_LEVEL, DB_HOST, DB_USER, API_BASE_URL, DB_PASSWORD (only if no password file)
  files        FEATURES_FILE (default /etc/allcsvideos/features.properties), re-read every 2 s
               DB_PASSWORD_FILE (default /etc/secrets/db-password)
It never prints the password itself: only where it came from and its length.
Serves on port 8080:  GET /config -> the settings it is using right now (password masked).
"""
import json, os, socket, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

VERSION = os.environ.get("APP_VERSION", "0.0.0")
ENV = {k: os.environ.get(k, "") for k in ("APP_ENV", "LOG_LEVEL", "DB_HOST", "DB_USER", "API_BASE_URL")}
FEATURES_FILE = os.environ.get("FEATURES_FILE", "/etc/allcsvideos/features.properties")
PW_FILE = os.environ.get("DB_PASSWORD_FILE", "/etc/secrets/db-password")
features = {}


def log(msg, level="INFO", always=False):
    order = ["DEBUG", "INFO", "WARNING", "ERROR"]
    cur = ENV["LOG_LEVEL"] or "INFO"
    if always or order.index(level) >= order.index(cur if cur in order else "INFO"):
        print(time.strftime("%H:%M:%S"), level, msg, flush=True)


def password_source():
    if os.path.exists(PW_FILE):
        return f"file {PW_FILE} ({len(open(PW_FILE).read().strip())} chars)"
    if os.environ.get("DB_PASSWORD"):
        return f"env DB_PASSWORD ({len(os.environ['DB_PASSWORD'])} chars)"
    return "not set"


def read_features():
    out = {}
    try:
        for line in open(FEATURES_FILE):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return out


def watch_features():
    global features
    while True:
        f = read_features()
        if f != features:
            features = f
            log("features loaded: " + (", ".join(f"{k}={v}" for k, v in f.items()) or "(none)"))
        time.sleep(2)


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        log(f"GET {self.path} from {self.client_address[0]}", "DEBUG")
        if self.path != "/config":
            self.send_response(404); self.end_headers(); return
        body = json.dumps({"version": VERSION, "pod": socket.gethostname(), **{k.lower(): v for k, v in ENV.items()},
                           "db_password": password_source(), "features": features}, indent=2).encode() + b"\n"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    # the start-up summary is always printed, whatever the log level
    log(f"api {VERSION} starting · env={ENV['APP_ENV']} · log_level={ENV['LOG_LEVEL']}", always=True)
    log(f"database {ENV['DB_HOST']}:5432 · user {ENV['DB_USER']} · password from {password_source()}", always=True)
    log(f"public url {ENV['API_BASE_URL']}", always=True)
    threading.Thread(target=watch_features, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
