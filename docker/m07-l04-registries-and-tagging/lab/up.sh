#!/usr/bin/env bash
# lab/up.sh: starts the M07-L04 lab on your laptop and prepares it, the same way the video's lab was set up.
#
#   registry   CNCF Distribution registry:3.1.2 on localhost:5001 ("the CI registry"). Port 5001 because macOS
#              uses 5000 for AirPlay Receiver. Manifest deletes are enabled for the garbage-collection step.
#              Data in the volume registry-data.
#   gitea      Gitea 28.1.0 with its built-in container registry: users, organisations, access tokens and
#              package permissions, like GHCR. Web UI and registry on localhost:3000. Data in the volume gitea-data.
#
# Then it creates, inside Gitea (all FAKE lab values):
#   users        asha (admin), priya, prod-deploy (for production servers), ci-bot (for the pipeline);
#                password fake-lab-pass-<user> for each, so you can sign in to the web UI
#   organisation allcsvideos (private) with the repository allcsvideos/allcsvideos-api
#   teams        deployers (packages: read) with prod-deploy; ci (packages: write) with ci-bot
#   tokens       written to lab/.tokens/ (mode 600, git-ignored), never printed:
#                asha-admin (all scopes), asha-cli (write:package, write:repository), prod-deploy-pull (read:package),
#                ci-bot-push (write:package)
# and a git repository (default ~/allcsvideos-api, or set REPO_DIR) with the API's history up to the hook:
#   v1.4.0  Fri  Asha   health and whoami endpoints
#   v1.4.1  Mon  Priya  whoami shows the Course Copilot URL   <- needs COPILOT_URL, the broken build
#
# Needs: docker, git, curl, jq, python3. Free ports 5001 and 3000.   Undo everything with lab/down.sh.
set -euo pipefail
LAB="$(cd "$(dirname "$0")" && pwd)"
APP="$LAB/../app"
TOK="$LAB/.tokens"
REPO_DIR="${REPO_DIR:-$HOME/allcsvideos-api}"
GITEA=http://localhost:3000
LBL=(--label course=devops)

for c in docker git curl jq python3; do command -v "$c" >/dev/null || { echo "missing: $c"; exit 1; }; done
[ -e "$REPO_DIR" ] && { echo "$REPO_DIR already exists: remove it or set REPO_DIR"; exit 1; }

echo "== containers"
docker volume create "${LBL[@]}" registry-data >/dev/null
docker volume create "${LBL[@]}" gitea-data >/dev/null
docker run -d "${LBL[@]}" --name registry -p 127.0.0.1:5001:5000 \
  -v registry-data:/var/lib/registry \
  -e REGISTRY_STORAGE_DELETE_ENABLED=true \
  registry:3.1.2 >/dev/null
docker run -d "${LBL[@]}" --name gitea -p 127.0.0.1:3000:3000 -v gitea-data:/data \
  -e USER_UID=1000 -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 -e GITEA__security__INSTALL_LOCK=true \
  -e GITEA__server__ROOT_URL=$GITEA/ -e GITEA__server__DOMAIN=localhost -e GITEA__server__DISABLE_SSH=true \
  -e GITEA__service__DISABLE_REGISTRATION=true \
  -e GITEA__repository__DEFAULT_BRANCH=main \
  gitea/gitea:28.1.0 >/dev/null

echo -n "== waiting for Gitea"
for i in $(seq 1 60); do curl -fs $GITEA/api/healthz >/dev/null 2>&1 && break; echo -n .; sleep 2; done; echo

gx() { docker exec -u git gitea gitea "$@"; }
echo "== users"
for u in asha priya prod-deploy ci-bot; do
  a=(); [ "$u" = asha ] && a=(--admin)
  gx admin user create --username "$u" --email "$u@example.com" --password "fake-lab-pass-$u" \
    --must-change-password=false ${a[@]+"${a[@]}"} >/dev/null
done

echo "== tokens (into lab/.tokens, never printed)"
mkdir -p "$TOK"; chmod 700 "$TOK"
tok() { gx admin user generate-access-token --username "$1" --token-name "$2" --scopes "$3" --raw > "$TOK/$1-$2"; chmod 600 "$TOK/$1-$2"; }
tok asha admin all
tok asha cli write:package,write:repository,read:user
tok prod-deploy pull read:package
tok ci-bot push write:package,read:repository

api() { curl -s -X "$2" -H 'Content-Type: application/json' -H "Authorization: token $(cat "$TOK/$1")" "$GITEA/api/v1$3" ${4:+-d "$4"}; }
echo "== organisation, repository, teams"
api asha-admin POST /orgs '{"username":"allcsvideos","full_name":"allcsvideos.com","visibility":"private"}' | jq -r .username
api asha-admin POST /orgs/allcsvideos/repos '{"name":"allcsvideos-api","description":"allcsvideos.com API","default_branch":"main","private":true}' | jq -r .full_name
t1=$(api asha-admin POST /orgs/allcsvideos/teams '{"name":"deployers","permission":"read","units_map":{"repo.packages":"read"},"includes_all_repositories":false}' | jq .id)
t2=$(api asha-admin POST /orgs/allcsvideos/teams '{"name":"ci","permission":"write","units_map":{"repo.packages":"write","repo.code":"read"},"includes_all_repositories":true}' | jq .id)
api asha-admin PUT "/teams/$t1/members/prod-deploy"
api asha-admin PUT "/teams/$t2/members/ci-bot"
api asha-admin GET /orgs/allcsvideos/teams | jq -c '.[] | {name, permission, units_map}'

echo "== git history in $REPO_DIR"
mkdir -p "$REPO_DIR"
cp "$APP/app.py" "$APP/Dockerfile" "$APP/.dockerignore" "$APP/.gitignore" "$REPO_DIR/"
cd "$REPO_DIR"
git init -q -b main
git config user.name Asha; git config user.email asha@example.com    # this repository only
D1='2026-10-16 17:42:00 +0530'; D2='2026-10-19 11:08:00 +0530'
git add -A
GIT_AUTHOR_DATE="$D1" GIT_COMMITTER_DATE="$D1" git commit -qm 'api 1.4.0: health and whoami endpoints'
GIT_COMMITTER_DATE="$D1" git tag -a v1.4.0 -m 'api 1.4.0'
# Monday: Priya's change makes COPILOT_URL required (os.environ[...] raises KeyError when it is not set)
python3 - app.py <<'PY'
import sys; p = sys.argv[1]; s = open(p).read()
s = s.replace('VERSION = "1.4.0"', 'VERSION = "1.4.1"')
s = s.replace('HOST = socket.gethostname()\n', 'HOST = socket.gethostname()\nCOPILOT_URL = os.environ["COPILOT_URL"]  # Course Copilot base URL\n')
s = s.replace('{"api": HOST, "version": VERSION}', '{"api": HOST, "version": VERSION, "copilot": COPILOT_URL}')
open(p, 'w').write(s)
PY
GIT_AUTHOR_DATE="$D2" GIT_COMMITTER_DATE="$D2" git -c user.name=Priya -c user.email=priya@example.com \
  commit -qam 'whoami: show the Course Copilot URL'
GIT_COMMITTER_DATE="$D2" git -c user.name=Priya -c user.email=priya@example.com tag -a v1.4.1 -m 'api 1.4.1'
git remote add origin $GITEA/allcsvideos/allcsvideos-api.git
# push with the token as a one-off header: nothing is stored in git config or a credential file
git -c http.extraHeader="Authorization: token $(cat "$TOK/asha-cli")" push -q -u origin main --tags
git log --oneline --decorate
git checkout -q v1.4.0      # the hook starts on Friday's code

echo
echo "lab up: registry on localhost:5001, Gitea on $GITEA (sign in as asha / fake-lab-pass-asha)"
echo "repository: $REPO_DIR (checked out at v1.4.0)"
