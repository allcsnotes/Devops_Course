#!/bin/bash
# setup-root.sh: runs as root inside web-01 (called by up.sh). Prepares the "server" the lesson starts from.
set -e
L=/lesson
useradd -m -s /bin/bash -G sudo,adm asha
echo 'asha:demo-password-123' | chpasswd                         # FAKE demo password, for sudo in this sandbox only
useradd --system --no-create-home -s /usr/sbin/nologin allcs    # the API's own user (M02-L03)

# the API stand-in (reopens its logs on SIGHUP) and its settings
install -d -m 755 /opt/allcsvideos /srv/allcsvideos
install -m 755 $L/lab/api.py /opt/allcsvideos/api.py
printf '%s\n' '# allcsvideos API settings' 'APP_ENV=production' 'LOG_LEVEL=info' 'LOG_DIR=/data/logs' 'UPLOAD_DIR=/data/uploads' > /srv/allcsvideos/app.env
install -d -o allcs -g allcs -m 755 /data/uploads
install -d -o allcs -g adm -m 2750 /data/logs
for i in 1 2 3; do head -c 3145728 /dev/urandom > /data/uploads/lesson-0$i.mp4; done
chown allcs:allcs /data/uploads/*.mp4

# STAGED: a week of API log lines, never rotated (a generated sample, about 45 MB)
python3 $L/lab/gen_week.py /data/logs/api.log 46137344
chown allcs:adm /data/logs/api.log; chmod 640 /data/logs/api.log
install -m 644 $L/lab/allcsvideos-api.service /etc/systemd/system/allcsvideos-api.service
systemctl daemon-reload; systemctl enable --now allcsvideos-api.service

# nginx access log: the GENERATED SAMPLE from M02-L04, with last Monday's 73 checkout errors
mkdir -p /root/gen && cd /root/gen && python3 $L/lab/gen_logs.py . >/dev/null
install -o www-data -g adm -m 640 access.log /var/log/nginx/access.log
systemctl restart nginx

# Asha's scripts in ~/bin (Ubuntu's ~/.profile puts ~/bin on PATH for login shells)
install -d -o asha -g asha /home/asha/bin /home/asha/logs
install -o asha -g asha -m 755 $L/bin/morning-check.sh /home/asha/bin/morning-check.sh
install -o asha -g asha -m 755 $L/bin/backup-uploads.sh /home/asha/bin/backup-uploads.sh
