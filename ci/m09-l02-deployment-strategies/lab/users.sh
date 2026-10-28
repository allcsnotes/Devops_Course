#!/usr/bin/env bash
# users.sh <run-name> <seconds> : simulated users for one strategy run.
#  - resets prod-01 to blue-1..3 on 1.6.0 and clears the load balancer log (so every run starts the same)
#  - starts python:3.12.15-slim running users/traffic.py: 40 requests a second against http://prod-01/
#  - results land in ./runs/<run-name>.{csv,jsonl,txt} (the .txt summary appears when the run ends)
set -euo pipefail
cd "$(dirname "$0")"
name=${1:?usage: users.sh <run-name> <seconds>} secs=${2:?seconds}
mkdir -p runs
docker exec -u asha prod-01 bash -c 'cd ~/deploy && ./reset.sh 1.6.0 >/dev/null'
docker exec prod-01 sh -c ': > /srv/lb/log/lb.log'
sleep 2
docker run -d --rm --label course=devops --name users --network deploy-lab \
  -v "$PWD/users:/app:ro" -v "$PWD/runs:/out" python:3.12.15-slim \
  sh -c "python /app/traffic.py http://prod-01/ $secs /out/$name > /out/$name.txt" >/dev/null
echo "users running for $secs s -> runs/$name.*"
