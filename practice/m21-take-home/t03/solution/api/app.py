"""api: the allcsvideos course-list API for the Compose take-home (stdlib HTTP server + PostgreSQL + Redis).

GET /api/courses  courses from PostgreSQL, cached in Redis for 30 s (header X-Cache: HIT or MISS)
GET /healthz      200 only when PostgreSQL and Redis both answer, else 503
Settings: DB_HOST, DB_NAME, DB_USER, DB_PASSWORD_FILE (a file holding the password), REDIS_HOST, PORT (8080)
"""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg
import redis

with open(os.environ["DB_PASSWORD_FILE"], encoding="utf-8") as f:
    DB_PASSWORD = f.read().strip()
DSN = f"host={os.environ['DB_HOST']} dbname={os.environ['DB_NAME']} user={os.environ['DB_USER']} password={DB_PASSWORD} connect_timeout=2"
CACHE = redis.Redis(host=os.environ.get("REDIS_HOST", "redis"), socket_timeout=2)


def courses():
    cached = CACHE.get("courses")
    if cached:
        return json.loads(cached), "HIT"
    with psycopg.connect(DSN) as conn:
        rows = conn.execute("SELECT id, title FROM courses ORDER BY id").fetchall()
    data = [{"id": r[0], "title": r[1]} for r in rows]
    CACHE.setex("courses", 30, json.dumps(data))
    return data, "MISS"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            if self.path == "/healthz":
                with psycopg.connect(DSN) as conn:
                    conn.execute("SELECT 1")
                CACHE.ping()
                return self.reply(200, {"status": "ok"})
            if self.path == "/api/courses":
                data, hit = courses()
                return self.reply(200, data, {"X-Cache": hit})
            return self.reply(404, {"error": "not found"})
        except (psycopg.Error, redis.RedisError) as e:
            return self.reply(503, {"error": type(e).__name__})

    def reply(self, status, body, headers=None):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
