#!/usr/bin/env bash
# run-incident.sh <name>: the staged incident from the video.
#  - 180 s of traffic at 20 requests a second (load container -> runs/<name>.csv and runs/<name>-pool.csv)
#  - docker stats for the api and db containers about once a second (runs/<name>-stats.csv)
#  - at 75 s, db/migration.sql runs against the catalog database and holds its lock for 30 s
#    (start/end times -> runs/<name>-migration.txt)
# Run it from this folder, with the lab up (docker compose up -d --build). Then: python3 signals.py <name>
set -euo pipefail
N=${1:?usage: run-incident.sh <name>}
cd "$(dirname "$0")"
docker compose cp db/migration.sql db:/tmp/migration.sql >/dev/null

# recorder: docker stats, about once a second, for 190 s
( F=runs/$N-stats.csv; : > "$F"; END=$(( $(date +%s) + 190 ))
  while [ "$(date +%s)" -lt "$END" ]; do
    T=$(python3 -c 'import time; print(int(time.time()*1000))')
    docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}' m16-lab-api-1 m16-lab-db-1 | sed "s/^/$T,/" >> "$F"
  done ) &

# the users (prints one summary line per second)
docker compose exec -T load python traffic.py http://api:8080 180 20 "$N" &

sleep 75
{ echo "start $(date +%H:%M:%S)"; docker compose exec -T db psql -U postgres -d catalog -f /tmp/migration.sql 2>&1; echo "end $(date +%H:%M:%S)"; } > "runs/$N-migration.txt"
wait
echo "run $N done: files in runs/"
