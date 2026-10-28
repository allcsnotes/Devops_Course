#!/bin/bash
# up.sh: builds what SURVIVES the disaster. Production itself is NOT built here: you build it in the lesson, from Git,
# with Terraform and bootstrap/cluster.sh, exactly like the video.
#
#   survivors: .5 git (Gitea)  .6 bucket (the off-site backup bucket)  .7 registry  .8 ops (Asha's and Rahul's laptop)
#              .9 students (start them with lab/students.sh)
#   production (built later): .10 db  .11 vault  .12 backup-agent  .13 prometheus  .14 grafana  .30 kind node
# Lab network dr-net 10.0.202.0/24. Ports on your laptop (127.0.0.1 only): 3001 Git, 9000 bucket, 5001 registry,
# and later 3000 Grafana, 9090 Prometheus. All passwords are FAKE lab values.
#
# The platform repo is pushed to Gitea as "runbook v1": the course's platform/ folder with the four drill-1 files from
# drill1/ on top. That is the version that fails in drill 1. You commit the fixes yourself later in the lesson.
# Students' files (acks.csv, requests.csv) go to $DATA (default ~/dr-lab-students).
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd); LESSON=$(cd "$H/.." && pwd)
DATA=${DATA:-$HOME/dr-lab-students}
P=dr; N=10.0.202; L=(--label course=devops)
exists(){ docker ps -a --format '{{.Names}}' | grep -qx "$1"; }
as(){ docker exec -i -u "$1" $P-ops bash -lc "$2"; }
gx(){ docker exec -u git $P-git gitea "$@"; }

# 1. images, network, volumes
for i in api bucket postgres backup-agent ops; do docker build -q "${L[@]}" -t $P-$i:1.0 "$H/images/$i" >/dev/null; done
docker network ls --format '{{.Name}}' | grep -qx $P-net || docker network create "${L[@]}" --subnet $N.0/24 $P-net >/dev/null
for v in git-data bucket registry; do docker volume ls -q | grep -qx $P-$v || docker volume create "${L[@]}" $P-$v >/dev/null; done

# 2. the survivors: Git server, off-site bucket, image registry, the ops laptop
exists $P-git || docker run -d "${L[@]}" --name $P-git --hostname git --network $P-net --ip $N.5 --memory 320m \
  -p 127.0.0.1:3001:3000 -v $P-git-data:/data -e USER_UID=1000 -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 -e GITEA__security__INSTALL_LOCK=true -e GITEA__server__ROOT_URL=http://$N.5:3000/ \
  -e GITEA__server__DOMAIN=$N.5 -e GITEA__server__DISABLE_SSH=true -e GITEA__service__DISABLE_REGISTRATION=true \
  -e GITEA__repository__DEFAULT_BRANCH=main -e GITEA__actions__ENABLED=false gitea/gitea:28.1.0 >/dev/null
exists $P-bucket || docker run -d "${L[@]}" --name $P-bucket --hostname bucket --network $P-net --ip $N.6 --network-alias bucket \
  --memory 96m -p 127.0.0.1:9000:9000 -v $P-bucket:/data $P-bucket:1.0 >/dev/null
docker run --rm "${L[@]}" -v $P-bucket:/data alpine:3.23.6 chown 10001 /data
exists $P-registry || docker run -d "${L[@]}" --name $P-registry --hostname registry --network $P-net --ip $N.7 --memory 96m \
  -p 127.0.0.1:5001:5000 -v $P-registry:/var/lib/registry registry:3.1.2 >/dev/null
mkdir -p "$DATA" && chmod 777 "$DATA"
exists $P-ops || docker run -d "${L[@]}" --name $P-ops --hostname ops --network $P-net --ip $N.8 --memory 768m \
  -v /var/run/docker.sock:/var/run/docker.sock -v "$DATA":/home/asha/students:ro -v "$LESSON":/home/asha/course:ro \
  -e TERM=xterm-256color $P-ops:1.0 >/dev/null
sleep 2; docker exec -u root $P-ops sh -c "mkdir -p /srv/drill && chmod 1777 /srv/drill"   # the shared drill log

# 3. our images in the registry (the database image with the WAL scripts, the backup agent, the API)
for i in postgres:18.6-wal:postgres backup-agent:1.0:backup-agent api:1.0:api; do
  r=${i%%:*}; rest=${i#*:}; tag=${rest%%:*}; src=${rest#*:}
  docker tag $P-$src:1.0 localhost:5001/allcs/$r:$tag && docker push -q localhost:5001/allcs/$r:$tag >/dev/null; done

# 4. Gitea: asha (admin), argocd-bot (read only), org allcsvideos, private repo platform
until docker exec $P-git curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
if ! gx admin user list | grep -q asha; then
  gx admin user create --username asha --email asha@example.com --password FAKE-lab-pass-asha --admin --must-change-password=false >/dev/null
  gx admin user create --username argocd-bot --email argocd-bot@example.com --password FAKE-lab-pass-bot --must-change-password=false >/dev/null
  A=$(gx admin user generate-access-token --username asha --token-name lab --scopes all --raw)
  B=$(gx admin user generate-access-token --username argocd-bot --token-name argocd --scopes read:repository --raw)
  api(){ docker exec $P-ops curl -s -X "$1" -H 'Content-Type: application/json' -H "Authorization: token $A" "http://$N.5:3000/api/v1$2" -d "$3"; }
  api POST /orgs '{"username":"allcsvideos","visibility":"public"}' >/dev/null
  api POST /orgs/allcsvideos/repos '{"name":"platform","description":"allcsvideos production: infra, cluster bootstrap, apps, DR runbook","private":true}' >/dev/null
  api PUT /repos/allcsvideos/platform/collaborators/argocd-bot '{"permission":"read"}' >/dev/null
  # the break-glass folder: lab only, on the laptop, never in Git, never next to the backups
  as asha "mkdir -p ~/break-glass && chmod 700 ~/break-glass && printf '%s' 'FAKE-lab-postgres-202' > ~/break-glass/db-admin-password"
  printf '%s' "$B" | docker exec -i -u asha $P-ops sh -c 'cat > ~/break-glass/argocd-git-token'
  printf 'http://asha:%s@%s.5:3000\n' "$A" $N | docker exec -i -u asha $P-ops sh -c 'cat > ~/.git-credentials && chmod 600 ~/.git-credentials ~/break-glass/*'
  printf 'http://argocd-bot:%s@%s.5:3000\n' "$B" $N | docker exec -i -u rahul $P-ops sh -c 'cat > ~/.git-credentials && chmod 600 ~/.git-credentials'
  for u in asha:Asha rahul:Rahul; do as ${u%%:*} "git config --global user.name ${u#*:} && git config --global user.email ${u%%:*}@example.com
    git config --global init.defaultBranch main && git config --global credential.helper store
    git config --global core.pager cat && git config --global advice.detachedHead false"; done
  unset A B
fi

# 5. the platform repo, "runbook v1", pushed once (Argo CD vendored from its pinned release)
as asha 'test -d ~/platform/.git || {
  cp -R ~/course/platform ~/platform && cp -R ~/course/drill1/. ~/platform/ && rm -f ~/platform/docs/drill-report.md
  curl -fsSL -o ~/platform/bootstrap/argocd/core-install-v3.5.6.yaml https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/manifests/core-install.yaml
  chmod +x ~/platform/dr/*.sh ~/platform/dr/*.py ~/platform/drill/*.sh ~/platform/bootstrap/*.sh ~/platform/infra/files/postgres/*.sh
  cd ~/platform && git init -q && git add . && git commit -qm "platform: infra, bootstrap, apps, DR runbook v1"
  git remote add origin http://10.0.202.5:3000/allcsvideos/platform.git && git push -q -u origin main; }'
as rahul 'test -d ~/platform/.git || git clone -q http://10.0.202.5:3000/allcsvideos/platform.git ~/platform'

echo "lab up. Asha:  docker exec -it -u asha -w /home/asha/platform $P-ops bash"
echo "       Rahul: docker exec -it -u rahul -w /home/rahul $P-ops bash"
