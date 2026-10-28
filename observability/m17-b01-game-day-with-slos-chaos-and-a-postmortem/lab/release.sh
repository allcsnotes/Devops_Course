#!/bin/bash
# release.sh VERSION: build the API image from the git tag vVERSION of app/ (a release is a tag, then an image)
set -euo pipefail
cd "$(dirname "$0")"
git -C app archive "v$1" | docker build -q -t "gameday-lab/api:$1" --label course=devops - | cut -c1-19
