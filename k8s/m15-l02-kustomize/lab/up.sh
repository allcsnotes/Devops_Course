#!/usr/bin/env bash
# Lab for M15-L02 (Kustomize): a one-node kind cluster "kustomize-lab" on Kubernetes 1.37, and the lab images
# allcsvideos/api and allcsvideos/storefront in versions 1.4.0 and 1.5.0, built locally and loaded into the node.
# Needs: Docker Desktop, kind v0.33.0, kubectl v1.37.x (Kustomize v5.8.1 built in), kustomize v5.8.3, git.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLUSTER=kustomize-lab
NODE_IMAGE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5

kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || \
  kind create cluster --name "$CLUSTER" --image "$NODE_IMAGE" --config "$HERE/kind-cluster.yaml" --wait 120s

for v in 1.4.0 1.5.0; do
  docker build -q --build-arg VERSION=$v -t allcsvideos/api:$v "$HERE/../app/api" >/dev/null
  docker build -q --build-arg VERSION=$v -t allcsvideos/storefront:$v "$HERE/../app/storefront" >/dev/null
done
kind load docker-image allcsvideos/api:1.4.0 allcsvideos/api:1.5.0 \
  allcsvideos/storefront:1.4.0 allcsvideos/storefront:1.5.0 --name "$CLUSTER"

kubectl get nodes
