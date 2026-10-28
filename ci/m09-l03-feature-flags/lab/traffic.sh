#!/usr/bin/env bash
# traffic.sh <name> <seconds> [rps] : 20 requests a second (default) through the load balancer, alternating /ask and
# /lessons/7/notes, for 1000 made-up users (u0001-u0005 staff, u0006-u0025 beta, the rest students).
# Prints one summary line per second; writes ./runs/<name>.csv (one row per request).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p runs
docker run --rm --label course=devops --name traffic --network flags-lab -v "$PWD/traffic:/t:ro" -v "$PWD/runs:/out" \
  python:3.12.15-slim python -u /t/traffic.py "${1:?name}" "${2:?seconds}" "${3:-20}"
