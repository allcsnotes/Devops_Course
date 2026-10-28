#!/usr/bin/env bash
# up.sh - the M09-L03 feature-flag lab, all in Docker on the network flags-lab:
#   web-01      "the server" (image flags-web01): the flag file /etc/flagd/flags.yaml, a local Git repo owned by asha
#   flagd       ghcr.io/open-feature/flagd:v0.18.0, watching that file (read-only)
#   model       LAB STAND-IN for the AI model service, with a switch to break it on purpose (POST /mode)
#   copilot-1/2 Course Copilot: FastAPI + OpenFeature SDK 0.10.0 + flagd provider 0.6.0
#   lb          nginx:1.29.8-alpine, round robin over the two replicas
# Work on web-01 as asha:  docker exec -it -u asha -w /etc/flagd web-01 bash
set -euo pipefail
cd "$(dirname "$0")"
L=(--label course=devops)
docker network create "${L[@]}" flags-lab >/dev/null
docker volume create "${L[@]}" flags-data >/dev/null
docker build -q "${L[@]}" -t flags-web01 image >/dev/null
docker build -q "${L[@]}" -t flags-model model >/dev/null
docker build -q "${L[@]}" --target runtime -t flags-copilot copilot >/dev/null
docker run -d --init "${L[@]}" --name web-01 --hostname web-01 --network flags-lab -v flags-data:/etc/flagd flags-web01 >/dev/null
# the flag file starts as a Git repository on web-01, owned by asha (the commit Friday's deploy shipped with)
docker cp flags/flags.yaml web-01:/etc/flagd/flags.yaml
docker cp flags/rollout-check.py web-01:/home/asha/rollout-check.py
docker exec web-01 sh -c 'chown -R asha:asha /etc/flagd /home/asha/rollout-check.py && chmod 755 /etc/flagd && chmod 644 /etc/flagd/flags.yaml'
docker exec -u asha -w /etc/flagd web-01 sh -c "git config --global user.name Asha && git config --global user.email asha@example.com && git config --global init.defaultBranch main && git init -q && git add . && git commit -qm 'flags: copilot-answers on, lesson-notes-v2 off (dark)'"
docker run -d "${L[@]}" --name flagd --hostname flagd --network flags-lab --network-alias flagd -v flags-data:/etc/flagd:ro \
  ghcr.io/open-feature/flagd:v0.18.0 start --uri file:/etc/flagd/flags.yaml >/dev/null
docker run -d "${L[@]}" --name model --hostname model --network flags-lab --network-alias model flags-model >/dev/null
for i in 1 2; do
  docker run -d "${L[@]}" --name copilot-$i --hostname copilot-$i --network flags-lab --network-alias copilot-$i \
    -e FLAGD_HOST=flagd -e FLAGD_PORT=8013 -e MODEL_URL=http://model:9000/answer flags-copilot >/dev/null
done
docker run -d "${L[@]}" --name lb --hostname lb --network flags-lab --network-alias lb \
  -v "$PWD/nginx:/etc/nginx/conf.d:ro" nginx:1.29.8-alpine >/dev/null
until docker exec web-01 curl -sf http://lb/health >/dev/null 2>&1; do sleep 1; done
echo "lab up"
