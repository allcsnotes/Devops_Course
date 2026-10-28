#!/usr/bin/env bash
# Removes only what lab/up.sh created: the helm-lab cluster, the helm-registry container and the two app images.
set -uo pipefail
kind delete cluster --name helm-lab
docker rm -fv helm-registry >/dev/null 2>&1 || true
docker rmi allcsvideos/api:2.4.0 allcsvideos/api:2.5.0 >/dev/null 2>&1 || true
echo "removed cluster helm-lab, container helm-registry and the allcsvideos/api images"
