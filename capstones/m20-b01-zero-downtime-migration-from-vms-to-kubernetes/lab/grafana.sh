#!/bin/bash
# grafana.sh: optional. Starts Grafana with the migration dashboard (needs about 600 MB of memory).
# Open http://localhost:3000 (anonymous viewer; the admin password is a FAKE lab value).
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd); P=mig
docker ps -a --format '{{.Names}}' | grep -qx $P-grafana || docker run -d --label course=devops --name $P-grafana \
  --hostname grafana --network $P-net --ip 10.0.201.31 --memory 768m -p 127.0.0.1:3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=fake-admin-pass-123 -e GF_AUTH_ANONYMOUS_ENABLED=true -e GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer \
  -e GF_ANALYTICS_REPORTING_ENABLED=false -e GF_ANALYTICS_CHECK_FOR_UPDATES=false -e GF_USERS_DEFAULT_THEME=dark \
  -v "$H/grafana/provisioning":/etc/grafana/provisioning:ro -v "$H/grafana/dashboards":/var/lib/grafana/dashboards:ro \
  grafana/grafana:13.2.4 >/dev/null
echo "Grafana: http://localhost:3000  (dashboard: allcsvideos > allcsvideos migration: VMs to Kubernetes)"
