"""Lab receiver: stands in for a pager and a ticket queue (no real calls). Standard library only.
Every Alertmanager notification becomes one JSON line in /data/notifications.log."""
import json, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        kind = self.path.strip("/")
        e = {"ts": time.strftime("%H:%M:%S"), "epoch": round(time.time(), 3), "kind": kind, "status": body.get("status"),
             "group": body.get("groupLabels"), "alerts": len(body.get("alerts", []))}
        line = json.dumps(e)
        print(("PAGE to asha: " if kind == "page" and e["status"] == "firing" else "") + line, flush=True)
        with open("/data/notifications.log", "a") as f:
            f.write(line + "\n")
        self.send_response(200); self.end_headers()

    def log_message(self, *a):
        pass


ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
