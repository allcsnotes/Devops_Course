#!/usr/bin/env bash
# Builds the lab image and starts the "web-01" server container.
# Then open a login shell as asha with:   docker exec -it web-01 su - asha
set -euo pipefail
cd "$(dirname "$0")"

docker build -t text-lab:1 .
docker rm -f web-01 >/dev/null 2>&1 || true          # start fresh if an old copy exists
docker run -d --name web-01 --hostname web-01 text-lab:1

echo
echo "web-01 is running. Log in as asha with:"
echo "  docker exec -it web-01 su - asha"
