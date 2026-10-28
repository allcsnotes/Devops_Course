#!/usr/bin/env bash
# lab/down.sh: removes everything lab/up.sh created (containers, volumes, tokens, the git repository).
# Images you built or pulled in the lesson are listed in the README's "Clean up" section.
set -uo pipefail
LAB="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${REPO_DIR:-$HOME/allcsvideos-api}"
docker rm -f prod registry gitea 2>/dev/null
docker buildx rm lab-builder 2>/dev/null
docker volume rm registry-data gitea-data 2>/dev/null
docker logout localhost:3000 >/dev/null 2>&1
rm -rf "$LAB/.tokens"
rm -rf "$REPO_DIR"
echo "lab down"
