#!/bin/bash
# PID 1 of the web-01 container. Runs every time the container starts:
#   1. fills the 64 MB data disk at /data (a tmpfs mounted by up.sh) until it is FULL. The full disk is STAGED on purpose.
#   2. starts the API as user allcs, in the background (this lab server has no systemd)
#   3. stays alive as a tiny init: a bash loop that also reaps finished processes
set -e

# the data disk: uploads and logs
install -d -o allcs -g allcs -m 755 /data/uploads
install -d -o allcs -g adm -m 2750 /data/logs
for i in 1 2 3; do head -c 3145728 /dev/urandom > /data/uploads/lesson-0$i.mp4; done
chown allcs:allcs /data/uploads/*.mp4; chmod 644 /data/uploads/*.mp4
python3 /root/gen_fill.py /data/logs/api.log.1 16777216 '2026-10-12 00:00:00'          # an old rotated log, 16 MB
python3 /root/gen_fill.py /data/logs/api.log 307200 '2026-10-19 00:00:01'              # the current log, 300 KB
python3 /root/gen_fill.py /data/logs/api-debug.log 999999999 '2026-10-19 11:42:00'     # debug log: until the disk is full
chown allcs:adm /data/logs/*; chmod 640 /data/logs/*
touch -d '2026-10-18 23:59:59' /data/logs/api.log.1
touch -d '2026-10-14 10:20:00' /data/uploads/lesson-01.mp4
touch -d '2026-10-16 18:05:00' /data/uploads/lesson-02.mp4
touch -d '2026-10-18 21:40:00' /data/uploads/lesson-03.mp4

# start the API as allcs, the classic Debian way
start-stop-daemon --start --background --chuid allcs --umask 027 --exec /usr/bin/python3 -- /opt/allcsvideos/api.py
sleep 1; df -h /data

# stay alive; exit cleanly on `docker stop`
trap 'exit 0' TERM
while :; do sleep 3600 & wait $!; done
