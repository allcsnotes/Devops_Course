#!/usr/bin/env bash
# check.sh: the reviewer's acceptance checks for task 2. Needs only the docker CLI.
#   bash check.sh [image-tag]     (default m21lab-t02-app:1.0.0)
set -uo pipefail
IMG=${1:-m21lab-t02-app:1.0.0}; C=m21lab-t02-run; MAX_MB=${MAX_MB:-55}
HADOLINT=hadolint/hadolint:v2.15.1
TRIVY=aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222
fails=0
ok(){ printf 'PASS %s\n' "$*"; }; bad(){ printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }
cleanup(){ docker rm -f "$C" >/dev/null 2>&1 || true; }; trap cleanup EXIT

docker run --rm -i "$HADOLINT" hadolint --no-color - < Dockerfile && ok "hadolint: no findings" || bad "hadolint findings"
docker build -q --target test -t m21lab-t02-app:test . >/dev/null && ok "tests pass in the test stage" || bad "test stage failed"
docker build -q --build-arg APP_VERSION=1.0.0 -t "$IMG" . >/dev/null || { bad "runtime build failed"; exit 1; }

user=$(docker image inspect -f '{{.Config.User}}' "$IMG")
[[ -n $user && ${user%%:*} != 0 && ${user%%:*} != root ]] && ok "runs as user $user" || bad "runs as root"
bytes=$(docker image inspect -f "{{.Size}}" "$IMG"); mb=$(( bytes / 1000 / 1000 ))
(( mb <= MAX_MB )) && ok "image content size ${mb} MB (limit ${MAX_MB} MB)" || bad "image size ${mb} MB > ${MAX_MB} MB"
docker image inspect -f '{{json .Config.Env}}' "$IMG" | grep -qi 'password\|secret\|token' \
  && bad "a secret-looking variable is baked into the image" || ok "no secret-looking variables in the image config"
docker run --rm --entrypoint python "$IMG" -c 'import pytest' >/dev/null 2>&1 \
  && bad "pytest is in the runtime image" || ok "no test tools in the runtime image"
docker run --rm --entrypoint python "$IMG" -m pip --version >/dev/null 2>&1 \
  && bad "pip is in the runtime image" || ok "no pip in the runtime image"

docker run -d --name "$C" --read-only --cap-drop ALL --security-opt no-new-privileges \
  -p 127.0.0.1:21051:8000 "$IMG" >/dev/null
for _ in $(seq 30); do [[ $(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$C") == healthy ]] && break; sleep 1; done
[[ $(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$C") == healthy ]] \
  && ok "healthy with --read-only, --cap-drop ALL, no-new-privileges" || bad "not healthy: $(docker logs --tail 3 "$C" 2>&1)"
body=$(docker run --rm --network container:"$C" curlimages/curl:8.17.0 -s 'http://127.0.0.1:8000/search?q=docker' 2>/dev/null || true)
[[ $body == *DevOps* ]] && ok "GET /search?q=docker -> $body" || bad "search answered: $body"
start=$(date +%s); docker stop -t 10 "$C" >/dev/null; secs=$(( $(date +%s) - start ))
code=$(docker inspect -f '{{.State.ExitCode}}' "$C")
(( secs < 5 )) && ok "stopped on SIGTERM in ${secs} s (exit code $code)" || bad "stop took ${secs} s (exit code $code): SIGTERM not handled"

if docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v m21lab-t02-trivy:/root/.cache "$TRIVY" image \
     --quiet --table-mode detailed --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 "$IMG"; then
  ok "trivy: no fixable HIGH or CRITICAL vulnerabilities"
else bad "trivy found fixable HIGH or CRITICAL vulnerabilities"; fi
printf '%d check(s) failed\n' "$fails"; (( fails == 0 ))
