#!/usr/bin/env bash
# release.sh VERSION: build the API image once, tag it three ways, push every tag
set -euo pipefail
VERSION=$1                                  # semver, e.g. 1.4.2
SHA=$(git rev-parse --short HEAD)           # short commit id
REPO=localhost:5001/allcsvideos/api
docker build -q \
  --label org.opencontainers.image.source=http://localhost:3000/allcsvideos/allcsvideos-api \
  --label org.opencontainers.image.revision="$(git rev-parse HEAD)" \
  --label org.opencontainers.image.version="$VERSION" \
  -t "$REPO:sha-$SHA" .
for t in "$VERSION" "${VERSION%.*}" "${VERSION%%.*}" latest; do   # 1.4.2 1.4 1 latest
  docker tag "$REPO:sha-$SHA" "$REPO:$t"
done
docker push --all-tags "$REPO"
