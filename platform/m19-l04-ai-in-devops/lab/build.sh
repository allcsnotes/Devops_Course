#!/usr/bin/env bash
# build.sh: build the lab images. One Dockerfile per service; the release number is baked in at build time.
#   allcs-catalog-api 1.4.2 (good) and 1.5.0 (the slow "trending" query, staged on purpose)
#   allcs-edge        2.3.0 and 2.3.1 (storefront-bff and course-copilot, same code)
#   allcs-ops         the ops box the AI scripts run in
set -euo pipefail
cd "$(dirname "$0")"
for v in 1.4.2 1.5.0; do docker build -q --label course=devops --build-arg APP_VERSION=$v -t allcs-catalog-api:$v app; done
for v in 2.3.0 2.3.1; do docker build -q --label course=devops --build-arg APP_VERSION=$v -t allcs-edge:$v edge; done
docker build -q -t allcs-ops:1 ops
