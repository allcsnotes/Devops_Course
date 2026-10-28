#!/usr/bin/env bash
# Builds the M05-L03 lab: one container, git-team, with three users (asha, priya, rahul) standing in for three laptops,
# and a bare repository /srv/git/allcsvideos-ops.git standing in for GitHub ("origin").
#  1. l01-repo.sh rebuilds allcsvideos-ops as M05-L01 left it.
#  2. setup.sh runs history.sh (M05-L02's three weeks of team history, built FOR THE DEMO with deliberate dates),
#     replays M05-L02's on-screen steps, tags v1.2.0 + branch release/1.2 (what the servers run), and gives Priya
#     a local, never-pushed branch feature/cert-check with four messy commits.
set -euo pipefail
cd "$(dirname "$0")"
C=git-team
if docker ps -a --format '{{.Names}}' | grep -qx "$C"; then
  echo "A container named $C already exists (another Git lesson's lab?). Run that lesson's lab/down.sh first." >&2; exit 1
fi
docker build -t git-team:m05l03 .
docker run -d --init --label course=devops-m05l03 --name $C --hostname lab git-team:m05l03 >/dev/null
for u in asha priya rahul; do
  name="$(tr '[:lower:]' '[:upper:]' <<<"${u:0:1}")${u:1}"
  docker exec -u $u $C sh -c "git config --global user.name '$name' && git config --global user.email $u@example.com && git config --global init.defaultBranch main && git config --global core.editor nano"
done
docker cp hc-toolkit $C:/opt/hc-toolkit
for f in l01-repo.sh history.sh flag-edit.sh setup.sh; do docker cp $f $C:/opt/$f; done
docker exec $C chmod -R a+rX /opt
docker exec -u asha $C bash /opt/l01-repo.sh
docker exec $C bash /opt/setup.sh
echo
echo "Lab is up. Open a laptop with, for example:"
echo "  docker exec -it -u asha -w /home/asha/allcsvideos-ops git-team bash"
