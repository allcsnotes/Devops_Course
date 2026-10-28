#!/usr/bin/env bash
# release.sh VERSION: bake, test, scan and push one golden image
set -euo pipefail
version=${1:?usage: release.sh VERSION}
image=allcs/web:$version
registry=localhost:5000

echo "== bake $image"
packer build -color=false -var "version=$version" \
  -var "revision=$(git rev-parse --short HEAD)" . > "packer-$version.log"
tail -n 1 "packer-$version.log"

echo "== test"
docker run -d --name web-test -e APP_ENV=staging "$image" > /dev/null
trap 'docker rm -f web-test > /dev/null' EXIT
sleep 1
docker exec web-test curl -fsS localhost/health
docker exec web-test hc --dry-run | tail -n 2

echo "== scan"
scripts/scan.sh "$image"

echo "== push"
docker tag "$image" "$registry/$image"
docker push -q "$registry/$image"
