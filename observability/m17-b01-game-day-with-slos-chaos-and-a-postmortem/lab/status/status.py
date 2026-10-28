"""Lab status page for allcsvideos (labelled LAB; stands in for a hosted status page). Standard library only.
The communications lead posts updates: POST /api/update {"component","state","status","message"}.
Every update is printed as one JSON line and appended to /data/status.log (the timeline uses it)."""
import html, json, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

COMP = {"Website": "operational", "Course catalog": "operational", "Course Copilot": "operational", "Video playback": "operational"}
LABEL = {"operational": "Operational", "degraded": "Degraded performance", "partial": "Partial outage", "major": "Major outage"}
COL = {"operational": "#1f9d55", "degraded": "#d69e2e", "partial": "#dd6b20", "major": "#e53e3e"}
updates = []


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, body, ctype="application/json"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path.startswith("/api"):
            return self.reply(200, json.dumps({"components": COMP, "updates": updates}, indent=1))
        worst = max(COMP.values(), key=list(LABEL).index)
        banner = "All systems operational" if worst == "operational" else "Some systems are affected"
        comps = "".join(f"<div class=c><span>{c}</span><b style='color:{COL[s]}'>{LABEL[s]}</b></div>" for c, s in COMP.items())
        ups = "".join(f"<div class=u><b>{u['status'].capitalize()}</b> · <span class=m>{u['ts']} IST</span><p>{html.escape(u['message'])}</p></div>"
                      for u in reversed(updates))
        self.reply(200, f"""<!doctype html><html><head><meta charset=utf-8><title>allcsvideos status (lab)</title><style>
body{{background:#f7f8fa;color:#1a202c;font:17px/1.5 system-ui,sans-serif;margin:0}}.w{{max-width:860px;margin:0 auto;padding:30px 24px}}
h1{{font-size:28px;margin:0}}.lab{{display:inline-block;background:#fefcbf;color:#744210;font-size:13px;font-weight:700;padding:3px 10px;border-radius:10px;margin-left:10px;vertical-align:middle}}
.b{{margin:22px 0;padding:18px 22px;border-radius:10px;color:#fff;font-weight:700;font-size:20px;background:{COL[worst]}}}
.c{{display:flex;justify-content:space-between;padding:14px 18px;background:#fff;border:1px solid #e2e8f0;margin-top:-1px}}
.u{{background:#fff;border:1px solid #e2e8f0;border-radius:10px;padding:14px 18px;margin-top:12px}}.u p{{margin:6px 0 0}}.m{{color:#718096}}
</style></head><body><div class=w><h1>allcsvideos.com status<span class=lab>LAB · not a real status page</span></h1>
<div class=b>{banner}</div>{comps}<h2 style="font-size:20px;margin-top:30px">Incident updates</h2>{ups or '<p class=m>No incidents reported.</p>'}</div></body></html>""",
                   "text/html; charset=utf-8")

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        u = json.loads(self.rfile.read(n) or b"{}")
        if u.get("component") in COMP and u.get("state") in LABEL:
            COMP[u["component"]] = u["state"]
        u["ts"] = time.strftime("%H:%M:%S")
        updates.append(u)
        line = json.dumps({"epoch": round(time.time(), 3), **u})
        print(line, flush=True)
        with open("/data/status.log", "a") as f:
            f.write(line + "\n")
        self.reply(200, json.dumps({"ok": True, "posted": u["ts"]}))


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
