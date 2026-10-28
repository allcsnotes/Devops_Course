#!/usr/bin/env bash
# port-forward.sh - opens the lab's web UIs and APIs on localhost (Ctrl+C stops all of them):
#   Prometheus      http://localhost:9090   (rightsize.sh and the f00 query use it)
#   OpenCost API    http://localhost:9003   (cost.sh uses it)
#   OpenCost UI     http://localhost:9091
#   Grafana         http://localhost:3000   (anonymous viewer; dashboard folder "FinOps")
set -euo pipefail
trap 'kill 0' EXIT
kubectl -n monitoring port-forward svc/prometheus 9090:9090 &
kubectl -n opencost   port-forward svc/opencost   9003:9003 &
kubectl -n opencost   port-forward svc/opencost   9091:9090 &
kubectl -n monitoring port-forward svc/grafana    3000:3000 2>/dev/null &
wait
