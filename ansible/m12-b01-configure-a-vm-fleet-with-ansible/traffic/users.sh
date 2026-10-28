#!/usr/bin/env bash
# users.sh <name> <seconds>: simulated users (python:3.12.15-slim running traffic.py) send 40 requests a second
# to lb-01 for <seconds>, while you roll a release. Results: traffic/runs/<name>.{txt,csv,jsonl}
# Stop early with:  docker stop -t 30 fleet-users   (it finishes the requests in flight, then writes the files)
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); mkdir -p "$D/runs"
docker run -d --rm --label lab=fleet --name fleet-users --network fleet-net --ip 10.0.126.50 \
  -v "$D":/app:ro -v "$D/runs":/out python:3.12.15-slim \
  sh -c "exec python /app/traffic.py http://10.0.126.5/ $2 /out/$1 > /out/$1.txt" >/dev/null
echo "users running: $1 for $2 s (stop: docker stop -t 30 fleet-users; summary: cat traffic/runs/$1.txt)"
