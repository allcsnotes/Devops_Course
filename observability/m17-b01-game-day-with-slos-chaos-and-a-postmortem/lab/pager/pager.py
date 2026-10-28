"""Lab pager: a stand-in for PagerDuty or Opsgenie (no real phone calls). Standard library only.
Alertmanager posts to /alertmanager (severity=page) and /tickets (severity=ticket).
A page goes to the primary on-call. If nobody acknowledges it within ESCALATE_AFTER seconds, it escalates to the
secondary. Every event is printed as one JSON line and appended to /data/pager.log (the timeline uses it)."""
import html, json, os, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PRIMARY, SECONDARY = os.environ.get("PRIMARY", "asha"), os.environ.get("SECONDARY", "rahul")
ESC = int(os.environ.get("ESCALATE_AFTER", "120"))
LOG = "/data/pager.log"
pages, tickets, lock = [], [], threading.Lock()


def now():
    t = time.time()
    return time.strftime("%H:%M:%S", time.localtime(t)), t


def event(page, kind, **kw):
    hms, t = now()
    e = {"ts": hms, "epoch": round(t, 3), "event": kind, "page": page["id"] if page else None, **kw}
    if page:
        page["events"].append(e)
    line = json.dumps(e)
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")


def on_alerts(body, ticket=False):
    for a in body.get("alerts", []):
        name, fp = a["labels"].get("alertname"), a.get("fingerprint")
        with lock:
            if ticket:
                tickets.append(a)
                event(None, "ticket " + a["status"], alert=name, starts_at=a.get("startsAt"))
                continue
            p = next((p for p in pages if p["fp"] == fp and p["state"] != "resolved"), None)
            if a["status"] == "firing" and not p:
                p = {"id": len(pages) + 1, "fp": fp, "alert": name, "summary": a["annotations"].get("summary", ""),
                     "severity": a["labels"].get("severity"), "state": "triggered", "level": 0, "t": time.time(),
                     "starts_at": a.get("startsAt"), "events": []}
                pages.append(p)
                event(p, "triggered", alert=name, starts_at=a.get("startsAt"), summary=p["summary"])
                event(p, "notified", who=PRIMARY, role="primary")
            elif a["status"] == "resolved" and p:
                p["state"] = "resolved"
                event(p, "resolved", alert=name, ends_at=a.get("endsAt"))


def escalator():
    while True:
        time.sleep(2)
        with lock:
            for p in pages:
                if p["state"] == "triggered" and p["level"] == 0 and time.time() - p["t"] > ESC:
                    p["level"] = 1
                    event(p, "escalated", who=SECONDARY, role="secondary", after_s=ESC)
                    event(p, "notified", who=SECONDARY, role="secondary")


CSS = """body{background:#0d1117;color:#e6edf3;font:16px/1.45 system-ui,sans-serif;margin:0;padding:28px 36px}
h1{font-size:24px;margin:0 0 4px}.lab{color:#f0b429;font-weight:700}.mut{color:#8b949e}
table{border-collapse:collapse;margin:14px 0 24px;width:100%}td,th{border-bottom:1px solid #30363d;padding:8px 10px;text-align:left}
th{color:#8b949e;font-weight:600}.st{font-weight:700;padding:2px 10px;border-radius:12px}
.triggered{background:#5a1e1e;color:#ff7b72}.acknowledged{background:#4a3b0c;color:#f0b429}.resolved{background:#12361f;color:#3fb950}
code{font-family:ui-monospace,monospace}"""


def page_html():
    rows = "".join(
        f"<tr><td>#{p['id']}</td><td><span class='st {p['state']}'>{p['state']}</span></td><td><b>{html.escape(p['alert'])}</b><br>"
        f"<span class='mut'>{html.escape(p['summary'])}</span></td><td>{p['severity']}</td><td><code>"
        + "<br>".join(f"{e['ts']} {e['event']}{' → ' + e['who'] if e.get('who') else ''}" for e in p["events"])
        + "</code></td></tr>" for p in reversed(pages))
    return f"""<!doctype html><html><head><meta charset=utf-8><title>Lab pager</title><style>{CSS}</style></head><body>
<h1>allcsvideos on-call <span class=lab>· LAB PAGER</span></h1><div class=mut>stands in for PagerDuty or Opsgenie · no real calls are made</div>
<table><tr><th>schedule</th><th>this week</th><th>escalation</th></tr>
<tr><td>primary</td><td>{PRIMARY}</td><td>paged first</td></tr>
<tr><td>secondary</td><td>{SECONDARY}</td><td>paged if no ack within {ESC} s (a short lab setting; teams pick their own)</td></tr></table>
<table><tr><th>page</th><th>state</th><th>alert</th><th>severity</th><th>events</th></tr>{rows or '<tr><td colspan=5 class=mut>no pages</td></tr>'}</table>
<div class=mut>tickets (severity=ticket): {len(tickets)}</div></body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, body, ctype="application/json"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path.startswith("/api/pages"):
            return self.reply(200, json.dumps(pages, indent=1))
        self.reply(200, page_html(), "text/html; charset=utf-8")

    def do_POST(self):
        u = urlparse(self.path)
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        if u.path in ("/alertmanager", "/tickets"):
            on_alerts(body, ticket=u.path == "/tickets")
            return self.reply(200, '{"ok":true}')
        if u.path == "/ack":
            q = parse_qs(u.query)
            pid, who = int(q["page"][0]), q.get("who", [PRIMARY])[0]
            with lock:
                p = next((p for p in pages if p["id"] == pid), None)
                if not p or p["state"] != "triggered":
                    return self.reply(409, '{"ok":false,"why":"not triggered"}')
                p["state"] = "acknowledged"
                event(p, "acknowledged", who=who)
            return self.reply(200, json.dumps({"ok": True, "page": pid, "acknowledged_by": who}))
        self.reply(404, '{"error":"not found"}')


if __name__ == "__main__":
    threading.Thread(target=escalator, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
