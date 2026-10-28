#!/usr/bin/env bash
# up.sh: start the chaos + DR lab the way the video did
#   1. the database and the backup host   2. load the catalog (40 courses, 1,000,000 fake enrollments)
#   3. everything else (2 API replicas, nginx, students, Prometheus, Grafana)   4. db-test, the empty restore target
set -euo pipefail
cd "$(dirname "$0")"
chmod a+w data   # the students container (uid 10001) appends to data/acks.csv
docker compose up -d --build --wait db backup
docker compose exec -T -e PGPASSWORD=demo-password-123 backup psql -q -f - < db/seed.sql   # FAKE lab password
docker compose up -d --build --wait
docker compose --profile restore up -d --wait db-test
docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}'
