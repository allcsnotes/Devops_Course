"""allcsvideos API stand-in (from M06-L06; Python standard library only, a real HTTP service).
Like a real app it fails fast: if the database does not answer at start-up, it exits with code 1.

Config from environment variables:
  PORT        port to listen on (default 8080)
  DB_HOST     PostgreSQL host (default localhost), DB_PORT (default 5432)
  REDIS_HOST  Redis host (optional), REDIS_PORT (default 6379)
Checks are real network calls: the database check opens TCP and sends PostgreSQL's SSLRequest
(a real server answers one byte, N or S); the Redis check sends PING and expects +PONG.
Paths: /health (200 if every dependency answers, else 503), /whoami (which container answered).
"""
import json, os, signal, socket, struct, sys
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

VERSION = "1.1"
HOST = socket.gethostname()
DB = (os.environ.get("DB_HOST", "localhost"), int(os.environ.get("DB_PORT", "5432")))
REDIS = (os.environ.get("REDIS_HOST"), int(os.environ.get("REDIS_PORT", "6379")))


def log(msg):
    print(msg, flush=True)


def check_db():
    try:
        with socket.create_connection(DB, timeout=3) as s:
            s.sendall(struct.pack("!ii", 8, 80877103))  # SSLRequest
            r = s.recv(1)
        return "ok" if r in (b"N", b"S") else f"unexpected reply {r!r}"
    except Exception as e:
        return f"{type(e).__name__}: {e}"


def check_redis():
    try:
        with socket.create_connection(REDIS, timeout=3) as s:
            s.sendall(b"PING\r\n")
            r = s.recv(16)
        return "ok" if r.startswith(b"+PONG") else f"unexpected reply {r!r}"
    except Exception as e:
        return f"{type(e).__name__}: {e}"


def health():
    body = {"api": HOST, "db": check_db()}
    if REDIS[0]:
        body["redis"] = check_redis()
    ok = all(v == "ok" for k, v in body.items() if k != "api")
    return (200 if ok else 503), body


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
            code, body = health()
        elif self.path == "/whoami":
            code, body = 200, {"api": HOST, "version": VERSION}
        else:
            code, body = 404, {"error": "not found"}
        self.send_json(code, body)
        log(f"GET {self.path} {code} from {self.client_address[0]}")


def main():
    signal.signal(signal.SIGTERM, lambda *a: sys.exit(0))  # docker stop: exit cleanly
    port = int(os.environ.get("PORT", "8080"))
    db = check_db()
    log(f"allcsvideos api {VERSION} on {HOST}: database {DB[0]}:{DB[1]} -> {db}")
    if db != "ok":
        log("cannot reach the database, exiting")
        sys.exit(1)
    if REDIS[0]:
        log(f"redis {REDIS[0]}:{REDIS[1]} -> {check_redis()}")
    log(f"listening on 0.0.0.0:{port}")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
