"""Lab stand-in for a pager, a ticket queue and a chat channel (M16-L06). No external services.
Alertmanager POSTs webhook JSON here; the path names the destination (/pager, /tickets, /chat, /heartbeat).
Each notification is logged as one line on stdout, and the full JSON is appended to /data/<path>.jsonl."""
import json, os, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
os.makedirs("/data", exist_ok=True)

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        dest = self.path.strip("/") or "root"
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        names = sorted({a["labels"].get("alertname", "?") for a in body["alerts"]})
        firing = sum(1 for a in body["alerts"] if a["status"] == "firing")
        print(f'{time.strftime("%H:%M:%S")} {dest:<9} {body["status"].upper():<8} alerts={len(body["alerts"])} '
              f'firing={firing} {",".join(names)}', flush=True)
        with open(f"/data/{dest}.jsonl", "a") as f:
            f.write(json.dumps({"received": time.strftime("%H:%M:%S"), **body}) + "\n")
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()

    def log_message(self, *a):
        pass

ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
