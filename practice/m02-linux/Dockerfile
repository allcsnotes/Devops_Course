# syntax=docker/dockerfile:1
# DevOps course, Module 02 practice sheet: the broken server web-01.
# Ubuntu 24.04 with systemd as PID 1, nginx, the allcsvideos API stand-in, OpenSSH.
# Everything below is broken ON PURPOSE. Reading this file spoils the tasks.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus procps psmisc sudo nginx python3 curl less nano \
      openssh-server openssh-client rsync lsof file cron \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- users and groups ----
RUN <<'EOF'
set -e
useradd -m -s /bin/bash -G sudo,adm asha
useradd -m -s /bin/bash priya
echo 'asha:demo-password-123' | chpasswd     # FAKE demo passwords, lab only
echo 'priya:demo-password-123' | chpasswd
groupadd devs
usermod -aG devs asha                         # priya should be in devs too, but isn't
useradd --system --no-create-home -s /usr/sbin/nologin allcs
echo 'asha ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/asha && chmod 0440 /etc/sudoers.d/asha   # lab convenience
# priya's narrow nginx rule: wrong path, wrong mode
echo 'priya ALL=(root) NOPASSWD: /usr/bin/nginx -t, /usr/bin/nginx -s reload' > /etc/sudoers.d/priya-nginx
chmod 0644 /etc/sudoers.d/priya-nginx
EOF

# ---- the site ----
COPY <<'EOF' /etc/nginx/sites-available/allcsvideos
server {
    listen 80;
    server_name allcsvideos.com www.allcsvideos.com;
    root /var/www/allcsvideos;
    index index.html;
    client_max_body_size 1m;

    location /api/ {
        proxy_pass http://127.0.0.1:8080/;
    }
}
EOF
COPY <<'EOF' /var/www/allcsvideos/index.html
<!doctype html>
<html><head><title>allcsvideos - learn computer science by video</title></head>
<body><h1>allcsvideos</h1><p>DevOps, DSA, System Design, Spring Boot, GenAI.</p></body></html>
EOF
COPY <<'EOF' /srv/allcsvideos/static/robots.txt
User-agent: *
Disallow: /api/
EOF
RUN <<'EOF'
set -e
ln -s /srv/allcsvideos/robots.txt /var/www/allcsvideos/robots.txt      # dangling: the file is in static/
# uploads: the forum "fix" was chmod -R 777, and somebody used it
install -d /var/www/allcsvideos/uploads
head -c 48213 /dev/urandom > /var/www/allcsvideos/uploads/thumb-devops.jpg
head -c 91877 /dev/urandom > /var/www/allcsvideos/uploads/notes-m02.pdf
echo '<?php system($_GET["cmd"]); ?>' > /var/www/allcsvideos/uploads/shell.php
chown nobody:nogroup /var/www/allcsvideos/uploads/shell.php
chmod -R 777 /var/www/allcsvideos/uploads
# the team release folder, created by a root deploy script
install -d -m 755 /srv/releases /srv/releases/v2.14.0
echo 'v2.14.0' > /srv/releases/v2.14.0/VERSION
# a new site build in asha's home, ready to deploy
install -d -o asha -g asha /home/asha/site /home/asha/site/static
echo '<h1>allcsvideos v2.15.0</h1>' > /home/asha/site/index.html
echo 'body{font-family:sans-serif}' > /home/asha/site/static/style.css
echo 'console.log("allcsvideos")' > /home/asha/site/static/app.js
chown -R asha:asha /home/asha/site
EOF

# ---- the API stand-in and its settings ----
COPY <<'EOF' /srv/allcsvideos/app.env
# allcsvideos API settings
APP_ENV=production
DB_HOST=db-01
DB_PASSWORD=demo-password-123
UPLOAD_DIR=/data/uploads
EOF
COPY <<'EOF' /opt/allcsvideos/api.py
#!/usr/bin/env python3
# allcsvideos API stand-in for the Linux lessons (port 8080). Settings come from /srv/allcsvideos/app.env.
#   GET  /health, GET /courses
#   POST /upload?name=X   stores the request body in UPLOAD_DIR/X
import json, os
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

S = {}
for line in open('/srv/allcsvideos/app.env'):
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        k, v = line.split('=', 1); S[k] = v

class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a): print('api:', fmt % a, flush=True)
    def reply(self, code, obj):
        b = (json.dumps(obj) + '\n').encode(); self.send_response(code)
        self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path == '/health': return self.reply(200, {'status': 'ok'})
        if self.path == '/courses': return self.reply(200, {'courses': ['devops', 'dsa', 'system-design']})
        self.reply(404, {'error': 'not found'})
    def do_POST(self):
        u = urlparse(self.path)
        if u.path != '/upload': return self.reply(404, {'error': 'not found'})
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        name = os.path.basename(parse_qs(u.query).get('name', ['upload.bin'])[0])
        path = os.path.join(S['UPLOAD_DIR'], name)
        try:
            with open(path, 'wb') as f: f.write(body)
        except OSError as e:
            try: os.remove(path)
            except OSError: pass
            return self.reply(507, {'error': f'upload failed: {e.strerror}'})
        self.reply(201, {'saved': name, 'bytes': len(body)})

print('allcsvideos-api: listening on port 8080', flush=True)
ThreadingHTTPServer(('', 8080), H).serve_forever()
EOF
COPY <<'EOF' /opt/allcsvideos/encoder.py
#!/usr/bin/env python3
# allcsvideos video encoder stand-in: writes a status line to /data/logs/encoder.log every 5 seconds.
# SIGHUP reopens the log file, like most daemons.
import signal, time
LOG = '/data/logs/encoder.log'
f = None
def reopen(*_):
    global f
    if f:
        try: f.close()
        except OSError: pass   # unwritten lines on a full disk are dropped
    f = open(LOG, 'a')
while True:
    try:
        reopen(); break
    except OSError:
        time.sleep(1)          # the data disk is not ready yet
signal.signal(signal.SIGHUP, reopen)
while True:
    try:
        f.write(time.strftime('%Y-%m-%dT%H:%M:%S') + ' encoder: queue empty, waiting\n'); f.flush()
    except OSError:
        pass
    time.sleep(5)
EOF
COPY <<'EOF' /home/priya/reindex.py
# search reindex, "quick test" - Priya
while True:
    pass
EOF
RUN <<'EOF'
set -e
chmod 755 /opt/allcsvideos/*.py
chmod 644 /srv/allcsvideos/app.env
chown priya:priya /home/priya/reindex.py
EOF

# ---- services ----
COPY <<'EOF' /etc/systemd/system/allcsvideos-api.service
[Unit]
Description=allcsvideos API
After=network.target

[Service]
User=allcs
ExecStart=/usr/bin/pyhton3 /opt/allcsvideos/api.py
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
COPY <<'EOF' /etc/systemd/system/allcsvideos-encoder.service
[Unit]
Description=allcsvideos video encoder

[Service]
User=allcs
ExecStart=/usr/bin/python3 /opt/allcsvideos/encoder.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
COPY <<'EOF' /etc/systemd/system/allcsvideos-reindex.service
[Unit]
Description=allcsvideos search reindex (temporary, Priya)

[Service]
User=priya
ExecStart=/usr/bin/python3 /home/priya/reindex.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF
# lab-stage: part of the lab, not a puzzle. At every boot it rebuilds the data disk (/data) and fills it.
COPY --chmod=755 <<'EOF' /usr/local/sbin/lab-stage
#!/bin/bash
# first boot only: two "backup" copies of the settings (made at first boot, so they behave like files on a normal disk)
if [ ! -e /var/lib/lab/backups-made ]; then
  ln /srv/allcsvideos/app.env /home/priya/app.env.old
  cp /srv/allcsvideos/app.env /var/backups/app.env.save
  chown priya:priya /var/backups/app.env.save && chmod 644 /var/backups/app.env.save
  mkdir -p /var/lib/lab && touch /var/lib/lab/backups-made
fi
install -d -o allcs -g allcs -m 755 /data/uploads
install -d -o allcs -g adm -m 2750 /data/logs
for i in 1 2 3; do head -c 3145728 /dev/urandom > /data/uploads/lesson-0$i.mp4; done
chown allcs:allcs /data/uploads/*.mp4
python3 - <<'PY'
import random
r = random.Random(7)
with open('/data/logs/api.log.1', 'w') as f:
    n = 0
    while f.tell() < 20 * 1024 * 1024:
        n += 1
        f.write(f'2026-10-18T{n // 3600 % 24:02d}:{n // 60 % 60:02d}:{n % 60:02d} DEBUG cache lookup '
                f'key=course:{r.randint(1, 240)}:lesson:{r.randint(1, 60)} hit={r.choice(["true", "false"])} took={r.randint(1, 9)}ms\n')
PY
chown allcs:adm /data/logs/api.log.1 && chmod 640 /data/logs/api.log.1
touch -d '2026-10-18 23:59:59' /data/logs/api.log.1
# wait until the encoder has its log open, then fill the disk through that log and delete its name
for i in $(seq 60); do
  pid=$(systemctl show -p MainPID --value allcsvideos-encoder)
  [ "$pid" != 0 ] && ls -l /proc/$pid/fd 2>/dev/null | grep -q encoder.log && break
  sleep 1
done
yes '2026-10-20T02:40:00 encoder: DEBUG frame buffer dump 0000000000000000000000000000' >> /data/logs/encoder.log 2>/dev/null
rm -f /data/logs/encoder.log
exit 0
EOF
COPY <<'EOF' /etc/systemd/system/lab-stage.service
[Unit]
Description=Practice lab: stage the data disk (part of the lab, not a task)
After=allcsvideos-encoder.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/lab-stage

[Install]
WantedBy=multi-user.target
EOF

# ---- the sample access log from last night (generated, not real traffic) ----
COPY <<'EOF' /root/gen_access_log.py
import random
from datetime import datetime, timedelta
r = random.Random(2026)
T0, END = datetime(2026, 10, 19, 22, 0, 0), datetime(2026, 10, 20, 4, 0, 0)
FULL, DOWN = datetime(2026, 10, 20, 2, 47, 0), datetime(2026, 10, 20, 2, 58, 30)
IPS = [f'203.0.113.{i}' for i in range(30, 70)] + [f'198.51.100.{i}' for i in range(10, 40)]
W = [1 / (i + 2) ** 0.8 for i in range(len(IPS))]
UA = ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/129.0', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) Safari/605.1.15',
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/129.0 Mobile', 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:131.0) Firefox/131.0']
UA_OF = {ip: r.choice(UA) for ip in IPS}
PAGES = [('GET', '/', 200, 18432, 10), ('GET', '/courses/devops', 200, 24117, 8), ('GET', '/courses/dsa', 200, 23980, 6),
         ('GET', '/static/app.js', 200, 187342, 8), ('GET', '/robots.txt', 404, 162, 2), ('GET', '/api/courses', 200, 61, 8),
         ('POST', '/api/checkout', 200, 44, 2), ('GET', '/videos/devops/lesson-03.m3u8', 200, 1210, 6)]
lines = []
def add(t, ip, m, p, st, b, ua=None):
    lines.append((t, f'{ip} - - [{t.strftime("%d/%b/%Y:%H:%M:%S")} +0000] "{m} {p} HTTP/1.1" {st} {b} "-" "{ua or UA_OF.get(ip, UA[0])}"'))
t = T0
while t < END:
    t += timedelta(seconds=r.randint(1, 7))
    ip = r.choices(IPS, W)[0]; m, p, st, b, _ = r.choices(PAGES, [x[4] for x in PAGES])[0]
    if p.startswith('/api/') and t >= DOWN: st, b = 502, 166
    add(t, ip, m, p, st, b)
# Meera uploads lessons: fine until the data disk fills at 02:47, then 507, then 502 once the API is down
MEERA = '203.0.113.25'
for hh, mm, ss, n, st in [(22, 41, 9, 2, 201), (23, 58, 40, 3, 201), (2, 47, 12, 4, 507), (2, 49, 55, 4, 507), (2, 53, 31, 4, 507),
                          (2, 56, 2, 4, 507), (3, 5, 44, 4, 502), (3, 12, 19, 4, 502)]:
    day = 19 if hh >= 22 else 20
    add(datetime(2026, 10, day, hh, mm, ss), MEERA, 'POST', f'/api/upload?name=lesson-0{n}.mp4', st, 166 if st == 502 else 52)
# password guessing against the login form
t = datetime(2026, 10, 19, 23, 30, 0)
while t < datetime(2026, 10, 20, 0, 15, 0):
    t += timedelta(seconds=r.randint(2, 4)); add(t, '192.0.2.66', 'POST', '/login', 401, 39, 'python-requests/2.32.3')
# a scanner, and the planted shell
SC = '192.0.2.14'
t = datetime(2026, 10, 20, 1, 12, 5)
for p, st in [('/wp-login.php', 404), ('/.env', 404), ('/xmlrpc.php', 404), ('/admin/', 404), ('/uploads/shell.php?cmd=id', 200),
              ('/uploads/shell.php?cmd=uname+-a', 200), ('/uploads/shell.php?cmd=cat+/etc/passwd', 200)]:
    t += timedelta(seconds=r.randint(20, 90)); add(t, SC, 'GET', p, st, 31 if st == 200 else 162, 'Mozilla/5.0 zgrab/0.x')
lines.sort()
with open('/var/log/nginx/access.log.1', 'w') as f:
    f.write(''.join(l + '\n' for _, l in lines))
EOF
RUN python3 /root/gen_access_log.py && rm /root/gen_access_log.py \
    && chown www-data:adm /var/log/nginx/access.log.1 && chmod 640 /var/log/nginx/access.log.1

# ---- SSH: a hardening file with a typo, and asha's key with a broken folder ----
COPY <<'EOF' /etc/ssh/sshd_config.d/10-hardening.conf
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthenticaton no
AllowUsers asha priya
EOF
RUN <<'EOF'
set -e
install -d -o asha -g asha -m 700 /home/asha/.ssh
su asha -c 'ssh-keygen -q -t ed25519 -N "" -C asha@web-01 -f /home/asha/.ssh/id_ed25519'
cp /home/asha/.ssh/id_ed25519.pub /home/asha/.ssh/authorized_keys
echo "localhost $(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)" > /home/asha/.ssh/known_hosts
chown -R asha:asha /home/asha/.ssh
chmod 600 /home/asha/.ssh/authorized_keys
chmod 777 /home/asha/.ssh                     # a forum "fix"
systemctl enable allcsvideos-api allcsvideos-encoder allcsvideos-reindex lab-stage
EOF

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
