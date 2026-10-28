# M07-L03 tools: Trivy, Syft and jq run from pinned images, nothing installed on your laptop.
# Load them into your current shell (bash or zsh):   source ./tools.sh
#
# - The Docker socket is mounted so the tool can read images from your local Docker.
#   That gives the tool control of Docker: fine on your laptop with a pinned image, not in CI
#   (there, scan a saved tarball with --input; see the README).
# - trivy-cache is a named volume that keeps Trivy's vulnerability database (about 130 MB) between runs.
# - The current folder is mounted at /work, so files like .trivyignore.yaml and SBOM output work.
# - Images are pinned by tag AND digest: a tag can be moved, a digest cannot.

TRIVY_IMG=aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222
SYFT_IMG=anchore/syft:v1.54.1@sha256:3eb5379ba7b409c3f4069b686110527af0c47df993fa5c10d13e7cf34f49b1aa
JQ_IMG=ghcr.io/jqlang/jq:1.8.1

trivy() {
  docker run --rm --label course=devops \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v trivy-cache:/root/.cache \
    -v "$PWD":/work -w /work \
    "$TRIVY_IMG" "$@"
}

syft() {
  docker run --rm --label course=devops \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PWD":/work -w /work \
    "$SYFT_IMG" "$@"
}

# skip this one if you already have jq installed
jq() {
  docker run --rm -i --label course=devops -v "$PWD":/work -w /work "$JQ_IMG" "$@"
}
