#!/usr/bin/env bash
# Removes everything lab/up.sh created: the kind cluster "lab" and the two local images.
set -uo pipefail
kind delete cluster --name lab
docker rmi catalog-api:2.4.0 catalog-api:2.5.0 2>/dev/null || true
