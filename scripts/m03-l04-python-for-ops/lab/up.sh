#!/usr/bin/env bash
# up.sh: the M03-L04 lab. One Docker network (lab-net) with three containers:
#   web-01      ubuntu:24.04, the server you log in to (Python 3.12 from Ubuntu, nginx, curl)
#   api-01      STAND-IN for the allcsvideos API, port 8080     (python:3.13.16-slim running services/standin.py)
#   copilot-01  STAND-IN for Course Copilot, port 8000          (same image and script)
set -euo pipefail
cd "$(dirname "$0")"
L=(--label course=devops)

# start clean: earlier lessons also use a container called web-01
docker rm -f web-01 api-01 copilot-01 >/dev/null 2>&1 || true
docker network rm lab-net >/dev/null 2>&1 || true

docker network create "${L[@]}" lab-net
docker run -d "${L[@]}" --name api-01 --hostname api-01 --network lab-net \
  -v "$PWD/services:/srv:ro" python:3.13.16-slim python -u /srv/standin.py api 8080
docker run -d "${L[@]}" --name copilot-01 --hostname copilot-01 --network lab-net \
  -v "$PWD/services:/srv:ro" python:3.13.16-slim python -u /srv/standin.py copilot 8000
# /data: a small 64 MB in-memory disk, as in the earlier lessons
docker run -d "${L[@]}" --name web-01 --hostname web-01 --network lab-net --init --tmpfs /data:size=64m \
  ubuntu:24.04 sleep infinity

docker cp .. web-01:/lesson               # this whole lesson folder, as /lesson inside web-01
docker exec web-01 bash /lesson/lab/setup-root.sh
echo
echo "Lab is ready. Log in as asha with:  docker exec -it web-01 su - asha"
