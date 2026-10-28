"""allcsvideos API stand-in for M06-L06 (Python standard library only, a real HTTP service).

Config from environment variables:
  PORT        port to listen on (default 8080)
  DB_HOST     PostgreSQL host (default localhost), DB_PORT (default 5432)
  REDIS_HOST  Redis host (optional), REDIS_PORT (default 6379)
Checks are real network calls: the database check opens TCP and sends PostgreSQL's SSLRequest
(a real server answers one byte, N or S); the Redis check sends PING and expects +PONG.
Paths: /health (200 if every dependency answers, else 503), /whoami (which container answered).
"""
import json, os, socket, struct, sys
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

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
            code, body = 200, {"api": HOST}
        else:
            code, body = 404, {"error": "not found"}
        self.send_json(code, body)
        log(f"GET {self.path} {code} from {self.client_address[0]}")


def main():
    port = int(os.environ.get("PORT", "8080"))
    log(f"allcsvideos api 1.0 on {HOST}, listening on 0.0.0.0:{port}")
    log(f"database {DB[0]}:{DB[1]} -> {check_db()}")
    if REDIS[0]:
        log(f"redis {REDIS[0]}:{REDIS[1]} -> {check_redis()}")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
