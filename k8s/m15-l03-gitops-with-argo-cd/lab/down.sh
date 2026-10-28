#!/usr/bin/env bash
# Removes only what lab/up.sh created: the argocd-lab cluster, the gitea container + volume, the lab images,
# and the argocd-bot token file.
set -uo pipefail
kind delete cluster --name argocd-lab
docker rm -f gitea >/dev/null 2>&1 || true
docker volume rm gitea-data >/dev/null 2>&1 || true
docker rmi allcsvideos/api:1.4.0 allcsvideos/api:1.5.0 allcsvideos/storefront:1.4.0 allcsvideos/storefront:1.5.0 >/dev/null 2>&1 || true
rm -rf ~/.argocd-lab
echo "removed cluster argocd-lab, gitea, its volume and the lab images"
