#!/usr/bin/env python3
# allcsvideos API stand-in for the Linux lessons (port 8080). Settings come from /srv/allcsvideos/app.env.
#   POST /upload?name=X  stores the request body in UPLOAD_DIR/X
#   LOG_LEVEL=debug      also writes a chatty debug log (LOG_DIR/api-debug.log), a few lines every second
#   SIGHUP               re-reads app.env and reopens the log files (like nginx and most daemons do)
import os, signal, threading, time, json, random
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

CFG = '/srv/allcsvideos/app.env'
S = {}; LOCK = threading.Lock(); LOGS = {}

def load():
    S.clear()
    for line in open(CFG):
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1); S[k] = v

def ts(): return time.strftime('%Y-%m-%dT%H:%M:%S')

def reopen():
    with LOCK:
        for f in LOGS.values():
            try: f.close()
            except OSError: pass        # unwritten lines on a full disk are dropped; the file is closed anyway
        LOGS.clear()
        LOGS['info'] = open(os.path.join(S['LOG_DIR'], 'api.log'), 'a')
        if S.get('LOG_LEVEL') == 'debug':
            LOGS['debug'] = open(os.path.join(S['LOG_DIR'], 'api-debug.log'), 'a')

def log(level, msg):
    with LOCK:
        f = LOGS.get('debug' if level == 'DEBUG' else 'info')
        if not f: return
        try: f.write(f'{ts()} {level} {msg}\n'); f.flush()
        except OSError: pass            # disk full: the line is lost, the API keeps running

def on_hup(sig, frm):
    load(); reopen(); log('INFO', f"SIGHUP: reloaded settings, reopened logs (LOG_LEVEL={S.get('LOG_LEVEL')})")

def chatter():
    r = random.Random(5)
    while True:
        time.sleep(0.25)
        log('DEBUG', f'cache lookup key=course:{r.randint(1, 240)}:lesson:{r.randint(1, 60)} hit={r.choice(["true", "false"])} took={r.randint(1, 9)}ms')

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, obj):
        b = (json.dumps(obj) + '\n').encode(); self.send_response(code)
        self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        log('INFO', f'GET {self.path}'); self.reply(200, {'status': 'ok'})
    def do_POST(self):
        u = urlparse(self.path); n = int(self.headers.get('Content-Length', 0)); body = self.rfile.read(n)
        if u.path == '/debug-burst':     # STAGING ONLY: writes MB megabytes of debug lines at once (used to refill the log on purpose)
            mb = int(parse_qs(u.query).get('mb', ['1'])[0]); line = 'cache lookup key=course:17:lesson:4 hit=false took=3ms'
            for _ in range(mb * 1024 * 1024 // 80): log('DEBUG', line)
            return self.reply(200, {'ok': True})
        if u.path != '/upload': return self.reply(404, {'error': 'not found'})
        name = os.path.basename(parse_qs(u.query).get('name', ['upload.bin'])[0]); path = os.path.join(S['UPLOAD_DIR'], name)
        try:
            with open(path, 'wb') as f: f.write(body)
        except OSError as e:
            try: os.remove(path)
            except OSError: pass
            log('ERROR', f'upload {name} failed: {e}')
            return self.reply(507, {'error': f'upload failed: {e.strerror}', 'file': name})
        log('INFO', f'upload {name} saved ({len(body)} bytes)'); self.reply(201, {'saved': name, 'bytes': len(body)})

load(); reopen(); signal.signal(signal.SIGHUP, on_hup)
log('INFO', f"allcsvideos-api started, LOG_LEVEL={S.get('LOG_LEVEL')}")
threading.Thread(target=chatter, daemon=True).start()
ThreadingHTTPServer(('', 8080), H).serve_forever()
