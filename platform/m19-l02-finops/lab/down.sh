#!/usr/bin/env bash
# down.sh - removes only what this lesson created: the kind cluster "finops" and the two lab images.
set -euo pipefail
kind delete cluster --name finops || true
docker rmi allcsvideos-api:1.0 allcsvideos-traffic:1.0 2>/dev/null || true
echo "removed cluster finops and the allcsvideos-api / allcsvideos-traffic images"
