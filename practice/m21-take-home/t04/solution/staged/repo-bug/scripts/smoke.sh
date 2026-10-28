#!/usr/bin/env bash
# smoke.sh IMAGE: start the image the way production does, wait for its health check, call one endpoint.
set -euo pipefail
image=${1:?usage: smoke.sh IMAGE}
name=smoke-$$
host=${SMOKE_HOST:-127.0.0.1}
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$name" --read-only --cap-drop ALL --security-opt no-new-privileges -p 18000:8000 "$image" >/dev/null
for _ in $(seq 30); do
  status=$(docker inspect -f '{{.State.Health.Status}}' "$name")
  [[ $status == healthy ]] && break
  sleep 1
done
echo "health: $status"
[[ $status == healthy ]]
curl -fsS --max-time 5 "http://$host:18000/search?q=docker"
echo
