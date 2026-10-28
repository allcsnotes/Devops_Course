#!/usr/bin/env bash
# scan.sh IMAGE...: the release gate. Trivy (pinned by digest, M07-L03) fails when an image has a
# CRITICAL vulnerability that already has a fix. Exit 0 = every image passed, 1 = at least one failed.
set -uo pipefail
TRIVY=aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222
TPL='{{range .}}{{range .Vulnerabilities}}      {{.PkgName}} {{.InstalledVersion}}  {{.VulnerabilityID}}  fixed in {{.FixedVersion}}{{"\n"}}{{end}}{{end}}'
docker volume create --label course=devops do-m07b01-trivy-cache > /dev/null   # vulnerability DB cache
failed=0
for img in "$@"; do
  if out=$(docker run --rm --label course=devops -v /var/run/docker.sock:/var/run/docker.sock \
       -v do-m07b01-trivy-cache:/root/.cache "$TRIVY" image -q --scanners vuln \
       --severity CRITICAL --ignore-unfixed --exit-code 1 --format template --template "$TPL" "$img" 2>&1); then
    echo "PASS  $img"
  else
    echo "FAIL  $img"; echo "$out"; failed=1
  fi
done
exit $failed
