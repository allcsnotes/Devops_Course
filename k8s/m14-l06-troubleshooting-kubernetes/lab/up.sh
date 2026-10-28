#!/usr/bin/env bash
# Builds the M14-L06 lab from scratch (about 3-5 minutes). Run from the lesson folder:  bash lab/up.sh
#   1. kind cluster "lab" (one control plane, one worker)
#   2. the catalog API image, versions 2.4.0 and 2.5.0, loaded into the nodes
#   3. namespace allcsvideos (made your default): API 2.4.0, storefront, probe pod - all healthy
#   4. a private registry on the worker (localhost:5001, basic auth, FAKE lab credentials) holding the admin image
#   5. namespace ops with a toolbox pod (dns-check) for the DNS demo
# Everything is broken on purpose later, by the steps in README.md - not here.
set -euo pipefail
cd "$(dirname "$0")/.."

REG_USER=ci-bot
REG_PASS=demo-registry-pass-123          # FAKE lab value
ADMIN_IMAGE=localhost:5001/allcsvideos/admin:1.0

echo "== 1. cluster"
kind get clusters | grep -qx lab || kind create cluster --config kind-cluster.yaml

echo "== 2. images"
for v in 2.4.0 2.5.0; do docker build -q --build-arg VERSION=$v -t catalog-api:$v app; done
kind load docker-image catalog-api:2.4.0 catalog-api:2.5.0 --name lab

echo "== 3. the healthy starting point"
kubectl create namespace allcsvideos --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace allcsvideos
kubectl apply -f manifests/base/
kubectl rollout status deployment/api --timeout=180s
kubectl rollout status deployment/storefront --timeout=180s
kubectl wait --for=condition=Ready pod/probe --timeout=180s

echo "== 4. private registry on the worker, with the admin image in it"
kubectl create namespace registry --dry-run=client -o yaml | kubectl apply -f -
HTPASSWD=$(docker run --rm python:3.13.16-alpine3.23 sh -c \
  "apk add -q --no-cache apache2-utils >/dev/null && htpasswd -Bbn $REG_USER $REG_PASS")
kubectl -n registry create secret generic registry-htpasswd --from-literal=htpasswd="$HTPASSWD" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f manifests/registry/registry.yaml
kubectl -n registry wait --for=condition=Ready pod/registry --timeout=180s
# Push the image from inside the worker node (the registry listens on the worker's 127.0.0.1:5001).
# It goes into a separate containerd namespace ("push"), so the kubelet does NOT already have it:
# the admin pod must really pull it - and fail until it has credentials.
docker tag catalog-api:2.5.0 $ADMIN_IMAGE
docker save $ADMIN_IMAGE | docker exec -i lab-worker ctr -n push images import -
docker exec lab-worker ctr -n push images push --plain-http --user "$REG_USER:$REG_PASS" $ADMIN_IMAGE
docker rmi $ADMIN_IMAGE >/dev/null

echo "== 5. namespace ops with a toolbox pod"
kubectl create namespace ops --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ops get pod dns-check >/dev/null 2>&1 || kubectl -n ops run dns-check --image nicolaka/netshoot:v0.16 -- sleep infinity
kubectl -n ops wait --for=condition=Ready pod/dns-check --timeout=180s

echo
kubectl get pods -o wide
echo "Lab ready. Continue with README.md, step 1."
