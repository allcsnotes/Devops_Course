#!/bin/bash
# up.sh: kind cluster "mock" (one node) with the catalog Deployment + Service (staged: wrong targetPort) and a
# client pod for testing from inside the cluster. Needs kind v0.33.0 and kubectl v1.37.1.
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd)
NODE_IMAGE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
kind get clusters 2>/dev/null | grep -qx mock || kind create cluster --name mock --image $NODE_IMAGE --config "$H/kind-cluster.yaml" --wait 180s
kubectl config use-context kind-mock >/dev/null
# multi-platform images can fail "kind load" (M13-L05): then the node pulls the image itself
docker pull -q python:3.13.16-slim >/dev/null && kind load docker-image python:3.13.16-slim --name mock || true
kubectl apply -f "$H/catalog.yaml"
kubectl config set-context --current --namespace=allcs >/dev/null
kubectl -n allcs rollout status deploy/catalog --timeout=180s
kubectl -n allcs get pod client >/dev/null 2>&1 || kubectl -n allcs run client --image=curlimages/curl:8.17.0 --command -- sleep infinity
kubectl -n allcs wait --for=condition=Ready pod/client --timeout=120s
echo "kind cluster mock up, namespace allcs"
