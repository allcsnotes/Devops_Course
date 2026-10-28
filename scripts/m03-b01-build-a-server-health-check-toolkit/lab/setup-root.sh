#!/bin/bash
# Runs as root inside the web-01 container (up.sh calls it for you).
# Result: a fresh web-01. nginx (the storefront) and the allcsvideos API stand-in run; hc is NOT installed yet.
# /data is web-01's small data disk: a 64 MB in-memory filesystem (tmpfs) that up.sh creates, as in M02-L05.
set -e
useradd -m -s /bin/bash -G sudo,adm asha
echo 'asha ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/asha && chmod 440 /etc/sudoers.d/asha   # lab only: no password prompts
useradd --system --no-create-home -s /usr/sbin/nologin allcs
install -d -m 755 /opt/allcsvideos && install -m 755 /tmp/lab/api.py /opt/allcsvideos/api.py
install -m 644 /tmp/lab/allcsvideos-api.service /etc/systemd/system/allcsvideos-api.service
systemctl daemon-reload && systemctl enable --now allcsvideos-api.service nginx.service
# some sample "videos" on the data disk, so /data is not empty
install -d -o allcs -g allcs -m 755 /data/uploads
for i in 1 2 3; do head -c 3145728 /dev/urandom > /data/uploads/lesson-0$i.mp4; done; chown allcs:allcs /data/uploads/*.mp4
# the toolkit folder Asha built, copied into her home
cp -r /tmp/hc /home/asha/hc && chown -R asha:asha /home/asha/hc
# print systemctl/journalctl output straight to the terminal, no pager
echo 'export SYSTEMD_PAGER=' >> /home/asha/.bashrc
