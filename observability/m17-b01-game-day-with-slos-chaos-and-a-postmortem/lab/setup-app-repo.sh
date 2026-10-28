#!/usr/bin/env bash
# setup-app-repo.sh: turn app/ into the git repo the video starts from:
#   v1.0 "course list, Copilot answers, worker pool" (Asha)   v1.1 "a featured course on the course list" (Priya)
# A release is a git tag; release.sh builds the image from the tag. Run it once, before release.sh.
set -euo pipefail
cd "$(dirname "$0")/app"
[ -d .git ] && { echo "app/ is already a git repo"; exit 0; }
git init -q -b main
git add Dockerfile requirements.txt api.py
GIT_AUTHOR_NAME=Asha GIT_AUTHOR_EMAIL=asha@example.com GIT_COMMITTER_NAME=Asha GIT_COMMITTER_EMAIL=asha@example.com \
  git commit -qm "catalog-api 1.0: course list, Copilot answers, worker pool"
git tag v1.0
cp ../versions/api-1.1.py api.py
git add api.py
GIT_AUTHOR_NAME=Priya GIT_AUTHOR_EMAIL=priya@example.com GIT_COMMITTER_NAME=Priya GIT_COMMITTER_EMAIL=priya@example.com \
  git commit -qm "catalog-api 1.1: a featured course on the course list"
git tag v1.1
git log --format="%h %d %s (%an)"
