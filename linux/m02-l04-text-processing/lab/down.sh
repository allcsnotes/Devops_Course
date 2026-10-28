#!/usr/bin/env bash
# Removes the "web-01" container and the lab image. Nothing else is touched.
set -uo pipefail
docker rm -f web-01 2>/dev/null || true
docker rmi text-lab:1 2>/dev/null || true
echo "Lab removed."
