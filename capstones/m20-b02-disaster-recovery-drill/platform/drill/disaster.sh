#!/usr/bin/env bash
# drill/disaster.sh: the STAGED disaster of the DR drill (run by the drill lead, never by the recovery team).
# Deletes the WHOLE production environment at once: the kind cluster, the database server AND its volume, Vault AND its
# data, the backup agent, Prometheus and Grafana with their volumes. No graceful shutdown: the database is killed.
# Survives by design: the off-site bucket, the Git server, the image registry, the ops laptop and the students.
set -uo pipefail
echo "$(date '+%F %T.%3N') DISASTER: production environment deleted (staged)" >> /srv/drill/events.log
echo "$(date +%T) DISASTER (staged): deleting production"
E=(dr-db dr-vault dr-backup-agent dr-prometheus dr-grafana)
docker kill "${E[@]}" >/dev/null &
kind delete cluster --name dr 2>&1 | sed 's/^/  /' &
wait
docker rm -f -v "${E[@]}" | sed 's/^/  removed container /'
docker volume rm dr-pgdata dr-vaultdata dr-tsdb dr-grafana | sed 's/^/  removed volume /'
echo "$(date +%T) production is gone. Left: $(docker ps --format '{{.Names}}' | grep -E '^dr-' | sort | tr '\n' ' ')"
