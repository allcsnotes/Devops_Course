#!/bin/bash
# Reconcile loop for ONE environment (lab stand-in for Argo CD).
#   ENV=dev|staging|prod, /run/secrets/repo-url = clone URL with the READ-ONLY deploy-bot token.
set -u
REPO_URL=$(cat /run/secrets/repo-url)
NET=lab-net
log(){ echo "$(date +%H:%M:%S) [$ENV] $*"; }
git clone -q "$REPO_URL" /repo 2>/dev/null || { log "clone failed"; sleep 5; exec bash /agent.sh; }
cd /repo; last=""
while true; do
  git fetch -q origin main 2>/dev/null && git reset -q --hard origin/main
  rev=$(git rev-parse --short HEAD)
  out=$(kustomize build envs/$ENV 2>&1) || { log "render failed at $rev: $out"; sleep 5; continue; }
  image=$(grep -m1 ' image: ' <<<"$out" | awk '{print $2}')
  replicas=$(grep -m1 'replicas: ' <<<"$out" | awk '{print $2}')
  appenv=$(grep -m1 ' APP_ENV: ' <<<"$out" | awk '{print $2}')
  loglvl=$(grep -m1 ' LOG_LEVEL: ' <<<"$out" | awk '{print $2}')
  want="$image|$replicas|$appenv|$loglvl"
  if [[ $want != "$last" ]]; then
    d=${image##*@}; log "git $rev: envs/$ENV wants api@${d:0:19} replicas=$replicas $appenv/$loglvl"
    docker pull -q "$image" >/dev/null || { log "pull failed: $image"; sleep 5; continue; }
    for i in $(seq 1 "$replicas"); do
      n=lab-$ENV-api-$i
      docker rm -f $n >/dev/null 2>&1
      docker run -d --name $n --hostname $ENV-api-$i --network $NET --network-alias api.$ENV \
        --label course=devops --label lesson=m19-l03 --memory 64m \
        -e APP_ENV="$appenv" -e LOG_LEVEL="$loglvl" "$image" >/dev/null
    done
    for n in $(docker ps -aq --filter name=^lab-$ENV-api-); do
      idx=$(docker inspect -f '{{.Name}}' $n | sed 's/.*-//'); (( idx > replicas )) && docker rm -f $n >/dev/null
    done
    last=$want; log "synced: $replicas running api@${d:0:19}"
  fi
  sleep 5
done
