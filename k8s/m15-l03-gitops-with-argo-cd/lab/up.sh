#!/usr/bin/env bash
# Lab for M15-L03 (GitOps with Argo CD):
#  - kind cluster "argocd-lab", one node, Kubernetes 1.36.4 (Argo CD 3.5 is tested on 1.33-1.36)
#  - lab images allcsvideos/api and allcsvideos/storefront, versions 1.4.0 and 1.5.0, loaded into the node
#  - Gitea 28.1.0 as the Git server: container "gitea" on the Docker network "kind" (the one the kind node uses),
#    so pods reach it as http://gitea:3000 and your laptop reaches it as http://localhost:3000
#  - Gitea accounts (FAKE lab passwords, only for this throwaway lab):
#      asha / fake-lab-pass-asha (admin), priya / fake-lab-pass-priya (write), argocd-bot / fake-lab-pass-argocd-bot (read)
#  - org "allcsvideos", PRIVATE repo "allcsvideos-deploy"; a read-only token for argocd-bot is written to
#    ~/.argocd-lab/argocd-bot-token (never printed)
# Needs: Docker Desktop, kind v0.33.0, kubectl, curl.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLUSTER=argocd-lab
NODE_IMAGE=kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed

# 1. cluster
kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || \
  kind create cluster --name "$CLUSTER" --image "$NODE_IMAGE" --config "$HERE/kind-cluster.yaml" --wait 120s

# 2. lab images
for v in 1.4.0 1.5.0; do
  docker build -q --build-arg VERSION=$v -t allcsvideos/api:$v "$HERE/../app/api" >/dev/null
  docker build -q --build-arg VERSION=$v -t allcsvideos/storefront:$v "$HERE/../app/storefront" >/dev/null
done
kind load docker-image allcsvideos/api:1.4.0 allcsvideos/api:1.5.0 \
  allcsvideos/storefront:1.4.0 allcsvideos/storefront:1.5.0 --name "$CLUSTER"

# 3. Gitea on the "kind" network
if ! docker ps -a --format '{{.Names}}' | grep -qx gitea; then
  docker volume create gitea-data >/dev/null
  docker run -d --name gitea --hostname gitea --network kind -p 127.0.0.1:3000:3000 -v gitea-data:/data \
    -e USER_UID=1000 -e USER_GID=1000 -e GITEA__database__DB_TYPE=sqlite3 -e GITEA__security__INSTALL_LOCK=true \
    -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea -e GITEA__server__DISABLE_SSH=true \
    -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__repository__DEFAULT_BRANCH=main \
    -e GITEA__actions__ENABLED=false gitea/gitea:28.1.0 >/dev/null
  until curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
  gx(){ docker exec -u git gitea gitea "$@"; }
  gx admin user create --username asha --email asha@example.com --password fake-lab-pass-asha --admin --must-change-password=false >/dev/null
  gx admin user create --username priya --email priya@example.com --password fake-lab-pass-priya --must-change-password=false >/dev/null
  gx admin user create --username argocd-bot --email argocd-bot@example.com --password fake-lab-pass-argocd-bot --must-change-password=false >/dev/null
  api(){ curl -s -u asha:fake-lab-pass-asha -H 'Content-Type: application/json' -X "$1" "http://localhost:3000/api/v1$2" -d "$3" >/dev/null; }
  api POST /orgs '{"username":"allcsvideos","visibility":"public"}'
  api POST /orgs/allcsvideos/repos '{"name":"allcsvideos-deploy","private":true,"default_branch":"main"}'
  api PUT /repos/allcsvideos/allcsvideos-deploy/collaborators/priya '{"permission":"write"}'
  api PUT /repos/allcsvideos/allcsvideos-deploy/collaborators/argocd-bot '{"permission":"read"}'
  mkdir -p ~/.argocd-lab && chmod 700 ~/.argocd-lab
  gx admin user generate-access-token --username argocd-bot --token-name argocd --scopes read:repository --raw \
    > ~/.argocd-lab/argocd-bot-token
  chmod 600 ~/.argocd-lab/argocd-bot-token
fi

kubectl get nodes
echo "Gitea: http://localhost:3000 (pods: http://gitea:3000)"
