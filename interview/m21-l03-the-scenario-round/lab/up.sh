#!/bin/bash
# up.sh cluster | incident
#   cluster   kind cluster "scenarios" for scenario 1 (pods keep restarting) and scenario 2 (deploys are slow)
#   incident  Docker Compose incident lab for scenario 3 (the site is down at 2 a.m.)
# Needs: Docker Desktop (with buildx), kind v0.33.0, kubectl v1.37.1. Everything runs locally, nothing costs money.
set -euo pipefail
H=$(cd "$(dirname "$0")/.." && pwd)
CLUSTER=scenarios
NODE_IMAGE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5

cluster() {
  # scenario 1: the catalog app (stdlib Python, ONE worker per pod) + search and thumbs, in namespace allcs
  docker build -q -t scenario-catalog:1.0 "$H/k8s/app" >/dev/null
  kind get clusters 2>/dev/null | grep -qx $CLUSTER \
    || kind create cluster --name $CLUSTER --image $NODE_IMAGE --config "$H/k8s/kind-cluster.yaml" --wait 180s
  kubectl config use-context kind-$CLUSTER >/dev/null
  docker pull -q python:3.13.16-slim >/dev/null
  kind load docker-image scenario-catalog:1.0 python:3.13.16-slim --name $CLUSTER
  kubectl apply -f "$H/k8s/manifests"
  kubectl -n lab create configmap traffic --from-file="$H/k8s/app/traffic.py" --from-file="$H/k8s/app/probe.py" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "$H/k8s/debug.yaml"                       # a debug pod next to the users, for probe.py
  kubectl config set-context --current --namespace=allcs >/dev/null
  kubectl -n allcs rollout status deploy/catalog --timeout=180s

  # scenario 2: a BuildKit builder for the pipeline, and catalog-api 1.5.0 running in namespace shop
  docker buildx inspect ci-builder >/dev/null 2>&1 \
    || docker buildx create --name ci-builder --driver docker-container --driver-opt image=moby/buildkit:v0.30.0 >/dev/null
  docker buildx build --builder ci-builder --load -t catalog-api:1.5.0 --build-arg APP_VERSION=1.5.0 "$H/pipeline/catalog-api"
  kind load docker-image catalog-api:1.5.0 --name $CLUSTER
  kubectl apply -f "$H/pipeline/shop.yaml"
  kubectl -n shop rollout status deploy/catalog-api --timeout=300s
  echo "cluster lab up: kubectl context kind-$CLUSTER, namespace allcs"
}

incident() {
  # scenario 3: two releases of the catalog API. 1.5.0 has the staged slow "trending" query.
  for v in 1.4.2 1.5.0; do docker build -q -t catalog-api:$v --build-arg APP_VERSION=$v "$H/incident/app" >/dev/null; done
  # first start loads 2,000,000 fake enrollments into PostgreSQL: give it a minute or two
  docker compose -f "$H/incident/compose.yaml" up -d --wait
  echo "incident lab up: api :8080  grafana :3000  prometheus :9090  alertmanager :9093  pager :8081  status page :8082"
}

case ${1:-} in
  cluster) cluster ;;
  incident) incident ;;
  *) sed -n '2,5p' "$0"; exit 1 ;;
esac
