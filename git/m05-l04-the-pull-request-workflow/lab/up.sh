#!/usr/bin/env bash
# Builds the M05-L04 lab:
#   git-lab     a Docker network
#   gitea       Gitea 28.1.0 (gitea/gitea:28.1.0): a real self-hosted Git server with web UI, REST API, pull requests,
#               reviews, branch protection and CODEOWNERS. Data in volume gitea-data. Web UI on http://localhost:3000
#               (published on 127.0.0.1 only); inside the lab its address is http://gitea:3000.
#   git-team    the team machine: users asha, priya, rahul, each with a clone of allcsvideos-ops, rebuilt with
#               l01-repo.sh + setup.sh (history built FOR THE DEMO, with deliberate dates). origin starts as a bare
#               repository in /srv/git, exactly like lessons 2 and 3; step 3 of the README moves it to Gitea.
# Then it creates the Gitea accounts asha (admin) and ci-bot, with the passwords from lab/accounts.env.
set -euo pipefail
cd "$(dirname "$0")"
[ -f accounts.env ] || { echo "First: cp lab/accounts.env.example lab/accounts.env, and set your own lab passwords in it." >&2; exit 1; }
# shellcheck disable=SC1091
. ./accounts.env
G=gitea C=git-team N=git-lab
L=(--label course=devops-m05l04)
for n in $G $C; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$n"; then
    echo "A container named $n already exists (another Git lesson's lab?). Run that lesson's lab/down.sh first." >&2; exit 1
  fi
done

docker network create "${L[@]}" $N >/dev/null
docker volume create "${L[@]}" gitea-data >/dev/null
docker run -d "${L[@]}" --name $G --hostname gitea --network $N --network-alias gitea -p 127.0.0.1:3000:3000 \
  -v gitea-data:/data \
  -e USER_UID=1000 -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 \
  -e GITEA__security__INSTALL_LOCK=true \
  -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea -e GITEA__server__DISABLE_SSH=true \
  -e GITEA__service__DISABLE_REGISTRATION=true \
  -e GITEA__ui__DEFAULT_THEME=gitea-dark \
  -e GITEA__repository__DEFAULT_BRANCH=main \
  -e GITEA__time__DEFAULT_UI_LOCATION=Asia/Kolkata \
  -e TZ=Asia/Kolkata \
  gitea/gitea:28.1.0 >/dev/null

docker build -t git-team:m05l04 .
docker run -d --init "${L[@]}" --name $C --hostname lab --network $N git-team:m05l04 >/dev/null
for u in asha priya rahul; do
  name="$(tr '[:lower:]' '[:upper:]' <<<"${u:0:1}")${u:1}"
  docker exec -u $u $C sh -c "git config --global user.name '$name' && git config --global user.email $u@example.com && git config --global init.defaultBranch main && git config --global core.editor nano && git config --global credential.helper store"
done
docker cp hc-toolkit $C:/opt/hc-toolkit
for f in l01-repo.sh history.sh flag-edit.sh setup.sh lab-ci.sh check-config.sh; do docker cp $f $C:/opt/$f; done
docker exec $C chmod -R a+rX /opt
docker exec $C chmod 755 /opt/check-config.sh
docker exec -u asha $C bash /opt/l01-repo.sh
docker exec $C bash /opt/setup.sh

echo "waiting for Gitea..."
until docker exec $G curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
docker exec -u git $G gitea admin user create --username asha --email asha@example.com --password "$LAB_PASS_ASHA" \
  --admin --must-change-password=false --fullname Asha >/dev/null
docker exec -u git $G gitea admin user create --username ci-bot --email ci-bot@example.com --password "$LAB_PASS_CI" \
  --must-change-password=false --fullname "lab CI" >/dev/null
echo
echo "Lab is up. Gitea: http://localhost:3000 (sign in as asha with your LAB_PASS_ASHA)."
echo "Next: create priya and rahul (README step 2), then run: bash lab/forge.sh"
