"""bucket.py: the OFF-SITE backup bucket for the M20-B02 drill (stands in for an S3 bucket in another account/region).
Objects live in /data (its own Docker volume, outside the production environment).
  PUT    /<key>            store an object. Backups are write-once: an existing key with different bytes -> 409
                           (tfstate/ keys may be replaced: Terraform's state is updated in place)
  POST   /<key>            same as PUT (Terraform's http backend writes state with POST)
  GET    /<key>            read an object (404 if missing)        GET /?prefix=wal/  list keys, newest last
  DELETE /<key>            only tfstate/ keys (backups can't be deleted through the API: immutable, lab version)
  GET    /metrics          bucket_objects{prefix}, bucket_newest_object_timestamp_seconds{prefix}
"""
import os, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

ROOT = "/data"
PREFIXES = ("wal", "base", "vault", "tfstate")


def path_of(key):
    p = os.path.normpath(os.path.join(ROOT, key))
    if not p.startswith(ROOT + "/") or ".." in key:
        raise ValueError("bad key")
    return p


def listing(prefix):
    out = []
    for d, _, files in os.walk(ROOT):
        for f in files:
            full = os.path.join(d, f)
            k = os.path.relpath(full, ROOT)
            if k.startswith(prefix) and not f.startswith(".tmp"):
                st = os.stat(full)
                out.append((st.st_mtime, k, st.st_size))
    return sorted(out)


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send(self, code, body=b"", ctype="text/plain"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/metrics":
            lines = []
            for p in PREFIXES:
                l = listing(p + "/")
                lines.append(f'bucket_objects{{prefix="{p}"}} {len(l)}')
                lines.append(f'bucket_bytes{{prefix="{p}"}} {sum(x[2] for x in l)}')
                if l:
                    lines.append(f'bucket_newest_object_timestamp_seconds{{prefix="{p}"}} {l[-1][0]:.3f}')
            return self.send(200, "\n".join(lines) + "\n")
        if u.path == "/":
            pre = parse_qs(u.query).get("prefix", [""])[0]
            rows = [f"{time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(m))} {s:>10} {k}" for m, k, s in listing(pre)]
            return self.send(200, "\n".join(rows) + ("\n" if rows else ""))
        try:
            p = path_of(u.path.lstrip("/"))
        except ValueError:
            return self.send(400, "bad key\n")
        if not os.path.isfile(p):
            return self.send(404, "no such object\n")
        with open(p, "rb") as f:
            self.send(200, f.read(), "application/octet-stream")

    def do_PUT(self):
        key = urlparse(self.path).path.lstrip("/")
        try:
            p = path_of(key)
        except ValueError:
            return self.send(400, "bad key\n")
        n = int(self.headers.get("Content-Length") or 0)
        data = self.rfile.read(n)
        if os.path.exists(p) and not key.startswith("tfstate/"):
            with open(p, "rb") as f:
                same = f.read() == data
            return self.send(200 if same else 409, "already stored\n" if same else "exists, different bytes\n")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        tmp = os.path.join(os.path.dirname(p), ".tmp-" + os.path.basename(p))
        with open(tmp, "wb") as f:
            f.write(data); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, p)
        print(f"{time.strftime('%H:%M:%S')} stored {key} ({len(data)} bytes)", flush=True)
        self.send(201, "stored\n")

    do_POST = do_PUT

    def do_DELETE(self):
        key = urlparse(self.path).path.lstrip("/")
        if not key.startswith("tfstate/"):
            return self.send(403, "backups are immutable\n")
        try:
            os.remove(path_of(key))
        except (FileNotFoundError, ValueError):
            pass
        self.send(200, "deleted\n")

    def log_message(self, *a):
        pass


print("off-site bucket on :9000, data in /data", flush=True)
srv = ThreadingHTTPServer(("0.0.0.0", 9000), H)
srv.daemon_threads = True
srv.serve_forever()
