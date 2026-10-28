#!/usr/bin/env bash
# Removes only what lab/up.sh created: the kustomize-lab cluster and the four lab images.
set -uo pipefail
kind delete cluster --name kustomize-lab
docker rmi allcsvideos/api:1.4.0 allcsvideos/api:1.5.0 allcsvideos/storefront:1.4.0 allcsvideos/storefront:1.5.0 >/dev/null 2>&1 || true
echo "removed cluster kustomize-lab and the lab images"
