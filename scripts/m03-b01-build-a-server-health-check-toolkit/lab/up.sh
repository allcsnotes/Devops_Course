#!/usr/bin/env bash
# up.sh: starts the lab for this lesson. Run it from anywhere: bash lab/up.sh
#   web-01 : Ubuntu 24.04 with systemd (nginx + the allcsvideos API stand-in on port 8080), user asha, ~/hc copied in
#   hooks  : a stand-in for a team chat webhook (python:3.13.16-slim running hooks.py on port 9000)
# Both sit on one Docker network, hc-lab, so web-01 reaches the webhook at http://hooks:9000/hc
set -euo pipefail
cd "$(dirname "$0")"

docker build -t hc-lab-web01 .
docker network create hc-lab

docker run -d --name hooks --hostname hooks --network hc-lab --network-alias hooks \
  -v "$PWD:/srv:ro" python:3.13.16-slim python -u /srv/hooks.py

# systemd in a container needs: --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock (from M02-L03)
# /data: a 64 MB in-memory disk, so we can fill it on purpose
docker run -d --name web-01 --hostname web-01 --network hc-lab --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /run/lock --tmpfs /data:rw,size=64m,mode=755 hc-lab-web01

sleep 6   # give systemd a moment to boot
docker cp . web-01:/tmp/lab
docker cp ../hc web-01:/tmp/hc
docker exec web-01 bash /tmp/lab/setup-root.sh

echo
echo "lab is up. Log in as asha:   docker exec -it web-01 su - asha"
echo "watch the team chat:         docker logs -f hooks"
