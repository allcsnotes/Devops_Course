#!/usr/bin/env bash
# seed.sh - pushes the two platform repositories to the lab Gitea, as asha:
#   allcsvideos/allcsvideos-platform  the course platform (a copy of the course repo's allcsvideos/ folder)
#                                     + the catalog descriptors from ../changes/
#   allcsvideos/golden-paths          the platform team's software template (../golden-paths/python-service)
# Works on temporary copies: the course repo's own allcsvideos/ folder is never changed.
set -euo pipefail
cd "$(dirname "$0")"
LESSON=$(cd .. && pwd); APP=$(cd ../../../allcsvideos && pwd)
TOKEN=$(cat secrets/asha.token)
AUTH="Authorization: Basic $(printf 'asha:%s' "$TOKEN" | base64 | tr -d '\n')"
api(){ curl -s -X "$1" -H 'Content-Type: application/json' -H "Authorization: token $TOKEN" "http://localhost:3000/api/v1$2" ${3:+-d "$3"}; }
WORK=$(mktemp -d)
cp -R "$APP" "$WORK/allcsvideos-platform"; cp -R "$LESSON/changes/." "$WORK/allcsvideos-platform/"
cp -R "$LESSON/golden-paths" "$WORK/golden-paths"
for r in allcsvideos-platform golden-paths; do
  api POST /orgs/allcsvideos/repos "{\"name\":\"$r\",\"default_branch\":\"main\"}" | jq -r .full_name
  msg="catalog: describe allcsvideos for the developer portal"; [ $r = golden-paths ] && msg="python-service: the first golden path"
  ( cd "$WORK/$r" && git init -q -b main && git add -A \
    && git -c user.name=Asha -c user.email=asha@example.com commit -q -m "$msg" \
    && git -c http.extraHeader="$AUTH" push -q http://gitea:3000/allcsvideos/$r.git main && git log --oneline )
done
rm -rf "$WORK"
