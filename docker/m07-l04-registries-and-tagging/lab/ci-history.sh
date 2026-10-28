#!/usr/bin/env bash
# lab/ci-history.sh: plays "the CI pipeline" before the retention step. A real pipeline pushes a sha-<commit> tag
# on every merge; this pushes one per commit of allcsvideos-api to the Gitea registry, as the ci-bot account.
# The release commit's sha tag must be the tested release build itself (not a rebuild), so it is replaced by a
# registry-to-registry copy of localhost:5001/allcsvideos/api:sha-<release>.
# Run it after the release (step 3) and after the multi-arch step. It leaves Docker logged in to Gitea as ci-bot.
set -euo pipefail
LAB="$(cd "$(dirname "$0")" && pwd)"
TOK="$LAB/.tokens"
REPO_DIR="${REPO_DIR:-$HOME/allcsvideos-api}"
G=localhost:3000/allcsvideos/api
cd "$REPO_DIR"
git diff --quiet || { echo "$REPO_DIR has uncommitted changes: git checkout app.py first"; exit 1; }

docker logout localhost:3000 >/dev/null 2>&1 || true
docker login localhost:3000 -u ci-bot --password-stdin < "$TOK/ci-bot-push" 2>/dev/null

commits=$(git rev-list --reverse --abbrev-commit HEAD)
for c in $commits; do
  git switch -q --detach "$c"
  docker build -q -t "$G:sha-$c" . >/dev/null
  docker push -q "$G:sha-$c"
  sleep 2
done
git switch -q main

release=$(git rev-parse --short HEAD)
curl -s -o /dev/null -X DELETE -H "Authorization: token $(cat "$TOK/asha-cli")" \
  "http://localhost:3000/api/v1/packages/allcsvideos/container/api/sha-$release"
docker buildx imagetools create -t "$G:sha-$release" "localhost:5001/allcsvideos/api:sha-$release" 2>/dev/null
echo "CI history pushed: $(echo $commits | sed 's/\([0-9a-f]*\)/sha-\1/g')"
