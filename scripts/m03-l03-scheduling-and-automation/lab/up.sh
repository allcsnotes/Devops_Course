#!/usr/bin/env bash
# up.sh: build the lab server web-01 for M03-L03 and prepare it.
#   web-01 = Ubuntu 24.04 with systemd as PID 1, cron and logrotate (see Dockerfile).
#   --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock : what systemd needs to run as PID 1 in a container
#   --tmpfs /data:size=64m : web-01's small data disk, a 64 MB in-memory filesystem (so it can really fill up)
set -euo pipefail
cd "$(dirname "$0")"

docker build -t web01-systemd --label course=devops .
docker rm -f web-01 >/dev/null 2>&1 || true
docker run -d --name web-01 --label course=devops --hostname web-01 --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /run/lock --tmpfs /data:rw,size=64m,mode=755 web01-systemd
sleep 5                                   # give systemd a moment to boot

docker cp .. web-01:/lesson               # this whole lesson folder, as /lesson inside web-01
docker exec web-01 bash /lesson/lab/setup-root.sh
echo
echo "web-01 is ready. Log in as asha with:  docker exec -it web-01 su - asha"
