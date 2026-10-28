#!/usr/bin/env bash
# Lab for M15-L01 (Helm): a one-node kind cluster "helm-lab" on Kubernetes 1.37,
# a local OCI registry on 127.0.0.1:5001 (for helm push / pull), and the catalog API
# built as allcsvideos/api:2.4.0 and :2.5.0 and loaded into the node.
# Needs: Docker Desktop, kind v0.33.0, kubectl v1.37.x, helm v4.3.1.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLUSTER=helm-lab
NODE_IMAGE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5

# 1. the cluster
kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || \
  kind create cluster --name "$CLUSTER" --image "$NODE_IMAGE" --config "$HERE/kind-cluster.yaml" --wait 120s

# 2. a local OCI registry for charts (lab only: plain HTTP)
docker ps -a --format '{{.Names}}' | grep -qx helm-registry || \
  docker run -d --name helm-registry -p 127.0.0.1:5001:5000 registry:3.1.2 >/dev/null

# 3. the app, two versions, loaded straight into the kind node (no registry pull needed)
for v in 2.4.0 2.5.0; do
  docker build -q --build-arg VERSION=$v -t allcsvideos/api:$v "$HERE/../app" >/dev/null
done
kind load docker-image allcsvideos/api:2.4.0 allcsvideos/api:2.5.0 --name "$CLUSTER"

kubectl get nodes
