#!/usr/bin/env bash
# down.sh: remove everything this lab created: containers, volumes (database, archive, backups), images, ack log
set -euo pipefail
cd "$(dirname "$0")"
docker compose --profile restore --profile pitr down -v
docker image rm chaos-lab/app:1.0 chaos-lab/backup:1.0 2>/dev/null || true
rm -f data/acks.csv
