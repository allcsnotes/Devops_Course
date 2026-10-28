#!/bin/bash
# down.sh: remove everything this lesson created (kind cluster, builder, incident lab, images, run logs).
H=$(cd "$(dirname "$0")/.." && pwd)
kind delete cluster --name scenarios 2>/dev/null || true
docker buildx rm ci-builder >/dev/null 2>&1 || true
docker compose -f "$H/incident/compose.yaml" --profile load down -v 2>/dev/null || true
docker rmi scenario-catalog:1.0 catalog-api:1.4.2 catalog-api:1.5.0 catalog-api:1.5.1 catalog-api:1.5.2 catalog-api:1.5.3 >/dev/null 2>&1 || true
rm -f "$H"/incident/incident/*.log "$H"/pipeline/catalog-api/.ci/*.log
echo "removed: kind cluster scenarios, builder ci-builder, compose project incident (+ volume), lab images, logs"
echo "(python, postgres, prometheus, grafana and kindest/node base images are kept; remove them with docker rmi if you want)"
