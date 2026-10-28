# tools.sh: the pinned tools of this lesson, as shell functions that run each tool's official image with Docker.
# Load them into your shell:   source ../tools.sh   (from inside copilot/)
# The current folder is mounted at /work. --network host lets the tools reach the lab registry on localhost:5001.
# Pins (all checked for the lesson on 2026-10-21): Trivy 0.76.0, uv 0.13.4, Syft 1.55.0, Grype 0.121.0, cosign 3.1.4.
TRIVY_IMG=aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222
UV_IMG=ghcr.io/astral-sh/uv:0.13.4-python3.13-trixie-slim
SYFT_IMG=anchore/syft:v1.55.0@sha256:4cc92b64ca74ffca4c94d4c8fcc01f217731375300be14d0b6eeb2e82eaa110a
GRYPE_IMG=anchore/grype:v0.121.0@sha256:621d56d1d68106b787022c81546f7e0a36202a25d1239f0c20195fab8c16f7ea
COSIGN_IMG=ghcr.io/sigstore/cosign/cosign:v3.1.4@sha256:0f06154836d2de34f887a5c273506d52ca43edaa1d9e53e6510fa78a48f69c2d
trivy()  { docker run --rm --label course=devops --network host -v /var/run/docker.sock:/var/run/docker.sock -v supplychain-trivy-cache:/root/.cache -v "$PWD":/work -w /work $TRIVY_IMG "$@"; }
uv()     { docker run --rm --label course=devops -v supplychain-uv-cache:/root/.cache/uv -v "$PWD":/work -w /work $UV_IMG uv "$@"; }
syft()   { docker run --rm --label course=devops --network host -e SYFT_REGISTRY_INSECURE_USE_HTTP=true -v "$PWD":/work -w /work $SYFT_IMG "$@"; }
grype()  { docker run --rm --label course=devops --network host -v supplychain-grype-cache:/root/.cache -v "$PWD":/work -w /work $GRYPE_IMG "$@"; }
cosign() { docker run --rm --label course=devops --network host -e COSIGN_PASSWORD -v "$PWD":/work -w /work $COSIGN_IMG "$@"; }
