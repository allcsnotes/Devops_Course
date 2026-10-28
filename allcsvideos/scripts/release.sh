#!/usr/bin/env bash
# release.sh VERSION: build every image once, gate it with Trivy, write SBOMs, tag it with the
# commit and the semver ladder, push to the registry, and record the digests (M07-L03, M07-L04).
set -euo pipefail
VERSION=${1:?usage: scripts/release.sh 1.2.3}
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "not a semver version: $VERSION" >&2; exit 2; }
[[ -z $(git status --porcelain) ]] || { echo "uncommitted changes: commit first" >&2; exit 2; }
SYFT=anchore/syft:v1.54.1@sha256:3eb5379ba7b409c3f4069b686110527af0c47df993fa5c10d13e7cf34f49b1aa
SERVICES=(storefront gateway catalog copilot)
export VERSION GIT_SHA=$(git rev-parse HEAD) GIT_URL=$(git remote get-url origin)
export IMAGE_PREFIX=${REGISTRY:-localhost:5001}/do-m07b01 TAG=sha-$(git rev-parse --short HEAD)

echo "== 1/5 build $TAG"
docker compose --profile copilot build --quiet "${SERVICES[@]}"
echo "== 2/5 gate: no fixable CRITICAL vulnerabilities"
IMAGES=(); for s in "${SERVICES[@]}"; do IMAGES+=("$IMAGE_PREFIX/$s:$TAG"); done
scripts/scan.sh "${IMAGES[@]}" || { echo "release $VERSION stopped: nothing was pushed" >&2; exit 1; }
echo "== 3/5 SBOMs"
mkdir -p dist/sbom
for s in "${SERVICES[@]}"; do
  docker run --rm --label course=devops -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD/dist/sbom":/out \
    "$SYFT" -q "$IMAGE_PREFIX/$s:$TAG" -o "spdx-json=/out/$s-$VERSION.spdx.json"
done
ls dist/sbom
echo "== 4/5 tag and push: $TAG $VERSION ${VERSION%.*} ${VERSION%%.*}"
for s in "${SERVICES[@]}"; do
  for t in "$VERSION" "${VERSION%.*}" "${VERSION%%.*}"; do docker tag "$IMAGE_PREFIX/$s:$TAG" "$IMAGE_PREFIX/$s:$t"; done
  for t in "$TAG" "$VERSION" "${VERSION%.*}" "${VERSION%%.*}"; do docker push -q "$IMAGE_PREFIX/$s:$t" > /dev/null; done
done
echo "== 5/5 digests (deploy these, not tags)"
for s in "${SERVICES[@]}"; do
  echo "$IMAGE_PREFIX/$s@$(docker buildx imagetools inspect "$IMAGE_PREFIX/$s:$VERSION" --format '{{.Manifest.Digest}}')"
done | tee "dist/release-$VERSION.txt"
