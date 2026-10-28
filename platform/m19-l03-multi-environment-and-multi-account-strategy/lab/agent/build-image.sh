#!/bin/bash
# build-image <version> : the CI build step from module 8, run in build-01 inside /work/allcsvideos-api.
# One image per commit, built and pushed ONCE. Prints the pushed digest.
set -eu
v=$1; rev=$(git rev-parse --short HEAD)
docker buildx build --progress=quiet --provenance=false --label course=devops --label lesson=m19-l03 \
  --build-arg APP_VERSION=$v --build-arg GIT_REV=$rev --build-arg BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --metadata-file /tmp/meta.json -t localhost:5001/allcsvideos/api:$v --push . >/dev/null
echo "pushed localhost:5001/allcsvideos/api:$v"
echo "digest $(jq -r '."containerimage.digest"' /tmp/meta.json)"
