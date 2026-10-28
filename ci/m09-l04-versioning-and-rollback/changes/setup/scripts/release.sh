#!/usr/bin/env bash
# release.sh VERSION: release the catalog service and its migrations as one version (M07-B01, M07-L04).
# The git tag vVERSION must point at HEAD: git tag = image tag = release. Deploy the recorded digests.
# This lesson's copy builds catalog + migrate only; the Trivy gate and SBOM steps of M07-B01 are left out.
set -euo pipefail
VERSION=${1:?usage: scripts/release.sh 1.2.3}
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "not a semver version: $VERSION" >&2; exit 2; }
[[ -z $(git status --porcelain) ]] || { echo "uncommitted changes: commit first" >&2; exit 2; }
[[ $(git describe --tags --exact-match 2>/dev/null) == "v$VERSION" ]] || { echo "HEAD is not tagged v$VERSION: tag the release first" >&2; exit 2; }
SERVICES=(catalog migrate)
export VERSION GIT_SHA=$(git rev-parse HEAD) GIT_URL=$(git remote get-url origin)
export IMAGE_PREFIX=${REGISTRY:-localhost:5001}/do-m07b01 TAG=sha-$(git rev-parse --short HEAD)

echo "== 1/3 build $TAG"
docker compose build --quiet "${SERVICES[@]}"
echo "== 2/3 tag and push: $TAG $VERSION"
for s in "${SERVICES[@]}"; do
  docker tag "$IMAGE_PREFIX/$s:$TAG" "$IMAGE_PREFIX/$s:$VERSION"
  for t in "$TAG" "$VERSION"; do docker push -q "$IMAGE_PREFIX/$s:$t" > /dev/null; done
done
echo "== 3/3 digests (deploy these, not tags)"
mkdir -p dist
for s in "${SERVICES[@]}"; do
  echo "$IMAGE_PREFIX/$s@$(docker buildx imagetools inspect "$IMAGE_PREFIX/$s:$VERSION" --format '{{.Manifest.Digest}}')"
done | tee "dist/release-$VERSION.txt"
