# allcsvideos API on web-01 (lab stand-in for the Spring Boot API). Python 3 standard library + psycopg2.
# GET /api/courses reads the course list from PostgreSQL on db-01 (a new connection per request, by name).
# Every request is appended to the access log in /var/log/allcs; errors go to the journal (stderr).
import json, os, sys, time, psycopg2
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = os.environ.get("LOG_FILE", "/var/log/allcs/api.log")
DB = dict(host=os.environ["DB_HOST"], dbname=os.environ["DB_NAME"], user=os.environ["DB_USER"],
          password=os.environ["DB_PASSWORD"], connect_timeout=3, application_name="allcs-api")

def err(msg):
    print(msg.strip().replace("\n", " "), file=sys.stderr, flush=True)

class H(BaseHTTPRequestHandler):
    def reply(self, code, body):
        b = (json.dumps(body) + "\n").encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        try:
            with open(LOG, "a") as f:
                f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} GET {self.path} from {self.headers.get('X-Real-IP', '-')}\n")
        except OSError as e:
            err(f"log write failed: {e}")
            return self.reply(500, {"error": "internal error"})
        if self.path == "/healthz":
            return self.reply(200, {"status": "ok"})
        if self.path == "/api/courses":
            try:
                with psycopg2.connect(**DB) as c, c.cursor() as cur:
                    cur.execute("SELECT title FROM courses ORDER BY id")
                    rows = [r[0] for r in cur.fetchall()]
                c.close()
                return self.reply(200, {"courses": rows})
            except psycopg2.Error as e:
                err(f"database error: {e}")
                return self.reply(503, {"error": "database unavailable"})
        self.reply(404, {"error": "not found"})
    def log_message(self, *a):
        pass

print(f"allcs-api listening on 127.0.0.1:8080, database {DB['host']}", flush=True)
ThreadingHTTPServer(("127.0.0.1", 8080), H).serve_forever()
