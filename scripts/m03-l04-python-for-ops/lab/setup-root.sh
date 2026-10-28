#!/bin/bash
# setup-root.sh: runs as root inside web-01 (called by up.sh). Prepares the "server" the lesson starts from.
# access.log is the GENERATED SAMPLE from M02-L04 (gen_logs.py), not real traffic.
set -e
L=/lesson
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq tmux nginx procps python3 python3-venv python3-pip curl sudo >/dev/null
useradd -m -s /bin/bash -G adm asha                       # adm: may read the logs in /var/log
mkdir -p /root/gen && cd /root/gen && python3 $L/lab/gen_logs.py .
install -o www-data -g adm -m 640 access.log /var/log/nginx/access.log
touch -d '2026-10-19 21:51:59' /var/log/nginx/access.log
chown asha:asha /data && chmod 755 /data
nginx                                                     # starts nginx (no systemd in this lab server)
install -d -o asha -g asha /data/uploads && fallocate -l 9M /data/uploads/lesson-05.mp4 && chown asha:asha /data/uploads/lesson-05.mp4   # a placeholder upload
echo 'asha ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/asha && chmod 440 /etc/sudoers.d/asha   # lab only: sudo without a password
# ~/reports from M03-L01 (the file with a space in its name)
su - asha -c 'mkdir -p ~/reports && printf "%s\n" "5xx on /api/checkout" "payment timeout" "release v2.14.0" "rolled back" "fixed" > ~/reports/"error report.txt"'
# the lesson scripts, in asha's home, as in the video (backup.py and quiet.py come later, in the pitfalls)
for f in api-check.sh httpcheck.py logstats.py healthcheck.py req.py; do install -o asha -g asha -m 755 $L/scripts/$f /home/asha/$f; done
install -o asha -g asha -m 644 $L/scripts/endpoints.json /home/asha/endpoints.json
