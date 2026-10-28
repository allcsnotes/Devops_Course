#!/bin/bash
# load.sh RUN [RATE] [DURATION]: the students (k6 2.3.0), on the lab network, through the edge (or BASE=... to bypass it).
# Pushes counters to Prometheus (remote write); writes one line per request to k6/out/RUN.log.
set -euo pipefail
RUN=$1; RATE=${2:-40}; DUR=${3:-5m}
: > ~/migration/k6/out/$RUN.log
echo "students: $RATE requests/s for $DUR (run $RUN)"
docker run --rm --name mig-k6 --label course=devops --network mig-net --ip 10.0.201.50 --memory 256m \
  -v "$(docker inspect mig-ops --format '{{range .Mounts}}{{if eq .Destination "/home/asha/migration"}}{{.Source}}{{end}}{{end}}')/k6:/k6" \
  -e K6_PROMETHEUS_RW_SERVER_URL=http://10.0.201.30:9090/api/v1/write -e K6_PROMETHEUS_RW_PUSH_INTERVAL=5s \
  -e RUN=$RUN -e RATE=$RATE -e DURATION=$DUR -e BASE=${BASE:-http://10.0.201.5} \
  grafana/k6:2.3.0 run --quiet --no-color -o experimental-prometheus-rw --tag testid=$RUN \
  --console-output=/k6/out/$RUN.log /k6/students.js
