#!/bin/bash
# up.sh: start round 1's server web-01 (Ubuntu 24.04 with systemd as PID 1, hostname web-01) and stage the fault.
# --privileged only because systemd runs as PID 1 inside the container (the M02-L03 recipe).
# ip_unprivileged_port_start=1024 restores the normal Linux rule that only privileged processes may bind ports below
# 1024 (Docker sets it to 0 inside containers).
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd); C=web-01
docker build -q --label course=devops -t web-01:1.0 "$H" >/dev/null
docker run -d --name $C --label course=devops --hostname web-01 --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /run/lock --sysctl net.ipv4.ip_unprivileged_port_start=1024 --memory 512m web-01:1.0 >/dev/null
until docker exec $C systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded'; do sleep 1; done
# staged fault: nginx stopped for "maintenance"; meanwhile Priya's preview server takes port 80
docker exec $C sh -c 'systemctl stop nginx; systemctl reset-failed; systemctl restart old-preview; sleep 2; journalctl --rotate -q; journalctl --vacuum-time=1s -q'
echo "web-01 up (staged: old-preview on :80, nginx stopped). Shell in with:"
echo "  docker exec -it -u asha -w /home/asha web-01 bash"
