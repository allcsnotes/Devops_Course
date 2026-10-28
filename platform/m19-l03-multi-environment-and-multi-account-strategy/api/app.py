# allcsvideos API stand-in for the promotion lab (stdlib only). Build facts are baked into the image at build
# time (APP_VERSION, GIT_REV, BUILT_AT); environment facts come from the environment at run time.
import json, os, socket
from http.server import BaseHTTPRequestHandler, HTTPServer

BAKED = {k: os.environ.get(k, "?") for k in ("APP_VERSION", "GIT_REV", "BUILT_AT")}

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            body = {"status": "ok"}
        elif self.path == "/version":
            body = {"version": BAKED["APP_VERSION"], "git": BAKED["GIT_REV"], "built": BAKED["BUILT_AT"],
                    "env": os.environ.get("APP_ENV", "?"), "log_level": os.environ.get("LOG_LEVEL", "?"),
                    "pod": socket.gethostname()}
        else:
            self.send_response(404); self.end_headers(); return
        data = (json.dumps(body) + "\n").encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self, *a):
        pass

HTTPServer(("0.0.0.0", 8080), H).serve_forever()
