#!/usr/bin/env bash
# install.sh: installs or updates hc on this server. Safe to run again.
set -euo pipefail
(( EUID == 0 )) || { echo "install.sh: run it with sudo" >&2; exit 1; }
src=$(dirname "$(readlink -f "$0")")

put() {   # put MODE SRC DEST: copy only when different, and say so
  if cmp -s "$2" "$3"; then echo "unchanged  $3"
  else install -D -m "$1" "$2" "$3"; echo "installed  $3"; fi
}

if id hc &>/dev/null; then echo "unchanged  user hc"
else useradd --system --no-create-home --shell /usr/sbin/nologin hc
     echo "created    user hc"; fi
install -d -o hc -g hc -m 750 /var/lib/hc
put 755 "$src/bin/hc" /opt/hc/bin/hc
for f in checks.sh http_check.py report.py; do
  put 644 "$src/lib/$f" "/opt/hc/lib/$f"
done
ln -sfn /opt/hc/bin/hc /usr/local/bin/hc
if [[ -e /etc/hc/hc.conf ]]; then echo "kept       /etc/hc/hc.conf"
else install -D -m 640 -g hc "$src/conf/hc.conf" /etc/hc/hc.conf
     echo "installed  /etc/hc/hc.conf"; fi
put 644 "$src/systemd/hc.service" /etc/systemd/system/hc.service
put 644 "$src/systemd/hc.timer" /etc/systemd/system/hc.timer
put 644 "$src/logrotate/hc" /etc/logrotate.d/hc
systemctl daemon-reload
systemctl enable --now hc.timer
echo "done: $(/opt/hc/bin/hc --version), timer enabled"
