#!/usr/bin/env bash
# up.sh - the M19-L02 FinOps lab on your laptop: one kind cluster called "finops" and the two lab images.
# Needs: Docker Desktop, kind v0.33.0, kubectl v1.37.1 (the versions the video used). Run from the lesson folder:
#   ./lab/up.sh
set -euo pipefail
cd "$(dirname "$0")/.."
CLUSTER=finops
NODE_IMAGE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5

kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || \
  kind create cluster --name "$CLUSTER" --image "$NODE_IMAGE" --config lab/kind-cluster.yaml --wait 300s

# the allcsvideos API (CPU-heavy /recommend endpoint) and the load generator, built locally and copied into the node
docker build -t allcsvideos-api:1.0 app
docker build -t allcsvideos-traffic:1.0 traffic
kind load docker-image allcsvideos-api:1.0 allcsvideos-traffic:1.0 --name "$CLUSTER"

kubectl get nodes
