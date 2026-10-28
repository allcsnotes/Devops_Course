#!/usr/bin/env bash
# deploy-gate.sh REF: resolve REF to a digest, verify its signature, and print the pinned reference to deploy.
# Exits non-zero (and deploys nothing) when the digest has no valid signature from our key.
set -euo pipefail
ref=${1:?usage: deploy-gate.sh REGISTRY/REPO:TAG}
COSIGN=(docker run --rm --network host -v "$PWD/keys:/keys:ro" -w /keys ghcr.io/sigstore/cosign/cosign:v3.1.4)   # an array: paths may contain spaces
digest=$(docker buildx imagetools inspect "$ref" --format '{{json .Manifest.Digest}}' | tr -d '"')
pinned="${ref%:*}@$digest"
echo "resolved $ref -> $digest"
if "${COSIGN[@]}" verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry "$pinned" >/dev/null 2>&1; then
  echo "signature OK: deploy ${pinned/localhost:21055/registry.lab:5000}"
else
  echo "REFUSED: $pinned has no valid signature from cosign.pub" >&2; exit 1
fi
