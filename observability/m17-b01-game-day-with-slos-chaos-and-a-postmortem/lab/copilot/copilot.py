"""Course Copilot, lab build: a keyword service, no AI model (like the platform repo's Copilot).
GET /ask?q=...  ->  {"answer": ..., "courses": [...]}.  Standard library only."""
import json, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

TOPICS = {"docker": ["Docker Deep Dive"], "kubernetes": ["Kubernetes in Production"], "linux": ["Linux Basics"],
          "terraform": ["Terraform"], "design": ["System Design"], "spring": ["Spring Boot"], "ai": ["Generative AI"],
          "dsa": ["Data Structures"], "devops": ["Linux Basics", "Docker Deep Dive", "Kubernetes in Production"]}


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/healthz":
            b = b"ok\n"
        else:
            q = parse_qs(u.query).get("q", [""])[0].lower()
            hits = next((v for k, v in TOPICS.items() if k in q), TOPICS["devops"])
            b = (json.dumps({"answer": f"Try: {', '.join(hits)}", "courses": hits, "model": "none (keyword match)"}) + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):
        pass


print("course copilot (keyword service, no AI model) on :8000", flush=True)
ThreadingHTTPServer(("0.0.0.0", 8000), H).serve_forever()
