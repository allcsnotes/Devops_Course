"""Lab load generator (M17-L01): students opening the course list on allcsvideos. Python standard library only.

  RATE   requests a second to the catalog API (default 10), 2-second client timeout
It also counts every request from the client's side and serves that count on :9000/metrics
(client_requests_total{result="ok"|"error"}), so Prometheus can compare the user's view with the server's.
Prints one summary line every 10 seconds.
"""
import os, threading, time, urllib.request
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

RATE = float(os.environ.get("RATE", "10"))
URL = os.environ.get("URL", "http://api:8080/api/courses")
stats = {"ok": 0, "error": 0}
lock = threading.Lock()


def hit():
    try:
        with urllib.request.urlopen(URL, timeout=2) as r:
            r.read()
        key = "ok"
    except Exception:          # HTTP 5xx, timeout, connection refused: the user saw an error
        key = "error"
    with lock:
        stats[key] += 1


class M(BaseHTTPRequestHandler):
    def do_GET(self):
        with lock:
            body = "# TYPE client_requests_total counter\n" + "".join(
                f'client_requests_total{{result="{k}"}} {v}\n' for k, v in stats.items())
        b = body.encode()
        self.send_response(200); self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

    def log_message(self, *a):
        pass


def main():
    print(f"loadgen: {RATE:g} req/s to {URL}", flush=True)
    threading.Thread(target=ThreadingHTTPServer(("0.0.0.0", 9000), M).serve_forever, daemon=True).start()
    i, start = 0, time.time()
    nxt = start + 10
    while True:
        threading.Thread(target=hit, daemon=True).start()
        i += 1
        time.sleep(max(0, start + i / RATE - time.time()))
        if time.time() >= nxt:
            nxt += 10
            with lock:
                print(time.strftime("%H:%M:%S"), f"ok {stats['ok']}  error {stats['error']}", flush=True)


if __name__ == "__main__":
    main()
