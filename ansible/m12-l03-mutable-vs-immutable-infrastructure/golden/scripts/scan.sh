#!/usr/bin/env bash
# scan.sh IMAGE: fail on fixable HIGH or CRITICAL vulnerabilities
# Trivy pinned by digest (module 7, lesson 3: the March 2026 tag compromise)
set -euo pipefail
trivy=aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v trivy-cache:/root/.cache "$trivy" image --quiet \
  --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 "${1:?usage: scan.sh IMAGE}"
