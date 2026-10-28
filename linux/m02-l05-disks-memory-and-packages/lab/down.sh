#!/usr/bin/env bash
# Removes the lab: the web-01 container (its /data disk disappears with it), the test-01 box if still there, and the image.
set -uo pipefail
docker rm -f web-01 test-01 2>/dev/null || true
docker rmi disk-lab:1 2>/dev/null || true
echo "Lab removed."
