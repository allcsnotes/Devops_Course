#!/usr/bin/env bash
# check.sh: the reviewer's acceptance checks for task 3. Needs only the docker CLI. Run it next to compose.yaml.
set -uo pipefail
P=m21lab-t03; URL=http://127.0.0.1:8080; fails=0
ok(){ printf 'PASS %s\n' "$*"; }; bad(){ printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }
# curl from a throwaway container on the host side of the published port (nothing installed on the laptop)
hcurl(){ docker run --rm --network container:${P}-proxy-1 curlimages/curl:8.17.0 "$@"; }

start=$(date +%s)
docker compose up -d --build --wait --wait-timeout 120 >/dev/null 2>&1 && ok "compose up --wait: all services healthy in $(( $(date +%s) - start )) s" || bad "compose up --wait failed"
docker compose ps --format '{{.Service}} {{.Status}}' | sort
pub=$(docker compose ps --format "{{.Ports}}" | grep -c -- "->" || true)
[[ $pub == 1 ]] && ok "exactly one service publishes a port" || bad "$pub services publish ports"
docker compose port proxy 8080 | grep -q '^127.0.0.1:' && ok "proxy is published on 127.0.0.1 only: $(docker compose port proxy 8080)" || bad "proxy is not bound to 127.0.0.1"

h1=$(hcurl -s -D - -o /dev/null $URL/api/courses | tr -d '\r' | grep -i '^x-cache' ); h2=$(hcurl -s -D - -o /dev/null $URL/api/courses | tr -d '\r' | grep -i '^x-cache')
[[ $h1 == *MISS* && $h2 == *HIT* ]] && ok "first request $h1, second $h2" || bad "cache headers: [$h1] [$h2]"
body=$(hcurl -s $URL/api/courses); [[ $body == *devops* ]] && ok "GET /api/courses through nginx returns the courses" || bad "body: $body"

docker run --rm --network ${P}_frontend postgres:18.6-alpine3.24 pg_isready -h db -t 3 >/dev/null 2>&1 \
  && bad "the database is reachable from the frontend network" || ok "the database is not reachable from the frontend network"
docker inspect ${P}-db-1 ${P}-api-1 --format '{{json .Config.Env}}' | grep -q 'demo-password' \
  && bad "the password is in a container's environment" || ok "no password in any container environment (secrets file instead)"

# a real crash: kill the API process (not "docker stop", which restart policies treat as manual)
docker compose exec -T api sh -c 'kill -KILL $(cat /proc/1/task/1/children)' >/dev/null 2>&1
code=$(hcurl -s -o /dev/null -w '%{http_code}' $URL/api/courses)
echo "     right after the crash, nginx answers $code"
for _ in $(seq 40); do [[ $(docker inspect -f '{{.State.Health.Status}}' ${P}-api-1) == healthy ]] && break; sleep 1; done
rc=$(docker inspect -f '{{.RestartCount}}' ${P}-api-1); code=$(hcurl -s -o /dev/null -w '%{http_code}' $URL/api/courses)
[[ $rc -ge 1 && $code == 200 ]] && ok "api crashed, was restarted (RestartCount=$rc) and serves again: HTTP $code" || bad "after crash: RestartCount=$rc HTTP $code"

docker compose exec -T db psql -U allcs -d allcs -qc "INSERT INTO courses VALUES ('k8s', 'Kubernetes in Production')" >/dev/null
docker compose down >/dev/null 2>&1; docker compose up -d --wait --wait-timeout 120 >/dev/null 2>&1
n=$(docker compose exec -T db psql -U allcs -d allcs -tAc "SELECT count(*) FROM courses")
[[ $n == 4 ]] && ok "data survives compose down and up (4 courses)" || bad "after down/up: $n courses"
printf '%d check(s) failed\n' "$fails"; (( fails == 0 ))
