#!/bin/bash
# setup.sh [DIR]: make two copies of Course Copilot (default ~/copilot-mock) for round 2's Docker question.
#   before/  the team's first Dockerfile (no .dockerignore)
#   after/   Asha's version: multi-stage, no compilers, no test tools, non-root, exec form, with .dockerignore
# The app itself (app/, data/, tests/, requirements*.txt) comes unchanged from the repo's allcsvideos/copilot.
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd); APP="$H/../../../allcsvideos/copilot"; DIR=${1:-$HOME/copilot-mock}
[ -d "$APP" ] || { echo "cannot find $APP"; exit 1; }
mkdir -p "$DIR"
for v in before after; do
  rm -rf "${DIR:?}/$v"; mkdir -p "$DIR/$v"
  cp -R "$APP/app" "$APP/data" "$APP/tests" "$APP/requirements.txt" "$APP/requirements-dev.txt" "$DIR/$v/"
  cp "$H/$v/Dockerfile" "$DIR/$v/"
done
cp "$H/after/.dockerignore" "$DIR/after/"
echo "ready: $DIR/before and $DIR/after"
