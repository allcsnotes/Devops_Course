#!/bin/zsh
# lab.sh up | push DIR MESSAGE | wait | logs JOB | down : a local CI lab for take-home task 4.
#  Gitea 28.1.0 (Gitea Actions runs GitHub Actions workflow syntax), the Gitea runner 5.1.1, and a separate
#  docker:29.5.3-dind daemon (TLS) for the jobs. Everything is named m21lab-t04-*. Lab-only FAKE password.
set -euo pipefail
H=${0:A:h}; SRC=${2:+${2:A}}   # resolve paths before cd
cd $H
V=m21lab-t04; N=$V-net; G=$V-gitea; D=$V-docker; R=$V-runner; L=(--label course=devops)
REPO=asha/course-search
api(){ docker run --rm --network $N curlimages/curl:8.17.0 -s -H "Authorization: token $(cat .token)" "http://gitea:3000/api/v1$1"; }
case ${1:-} in
up)
  docker network create $L $N >/dev/null
  for v in gitea-data dind-certs dind-data runner-data git; do docker volume create $L $V-$v >/dev/null; done
  docker run -d $L --name $G --hostname gitea --network $N --network-alias gitea -p 127.0.0.1:21054:3000 \
    --memory 384m -v $V-gitea-data:/data -e USER_UID=1000 -e USER_GID=1000 -e GITEA__database__DB_TYPE=sqlite3 \
    -e GITEA__security__INSTALL_LOCK=true -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea \
    -e GITEA__server__DISABLE_SSH=true -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__actions__ENABLED=true \
    -e GITEA__repository__DEFAULT_BRANCH=main gitea/gitea:28.1.0 >/dev/null
  docker run -d $L --name $D --hostname docker --network $N --network-alias docker --privileged --memory 1536m \
    -e DOCKER_TLS_CERTDIR=/certs -v $V-dind-certs:/certs -v $V-dind-data:/var/lib/docker docker:29.5.3-dind >/dev/null
  until docker exec $G curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
  docker exec -u git $G gitea admin user create --username asha --email asha@example.com \
    --password fake-lab-pass-asha --admin --must-change-password=false >/dev/null
  docker exec -u git $G gitea admin user generate-access-token --username asha --token-name lab --scopes all --raw > .token
  chmod 600 .token
  docker run --rm --network $N curlimages/curl:8.17.0 -s -o /dev/null -w 'create repo: HTTP %{http_code}\n' \
    -H "Authorization: token $(cat .token)" -H 'Content-Type: application/json' \
    -d '{"name":"course-search","default_branch":"main","auto_init":false}' http://gitea:3000/api/v1/user/repos
  tok=$(docker exec -u git $G gitea actions generate-runner-token | tail -1)
  docker run -d $L --name $R --hostname runner-01 --network $N --memory 256m \
    -v /var/run/docker.sock:/var/run/docker.sock -v $V-runner-data:/data -v $H/runner/config.yaml:/config.yaml:ro \
    -e CONFIG_FILE=/config.yaml -e GITEA_INSTANCE_URL=http://gitea:3000/ -e GITEA_RUNNER_REGISTRATION_TOKEN=$tok \
    -e GITEA_RUNNER_NAME=runner-01 gitea/runner:5.1.1 >/dev/null
  unset tok
  for i in {1..60}; do docker logs $R 2>&1 | grep -q 'declare successfully\|declared successfully' && break; sleep 1; done
  docker logs $R 2>&1 | grep -i 'declare' | tail -1
  echo lab up ;;
push)   # push DIR MESSAGE: replace the repo's files with DIR and push one commit
  docker run --rm --network $N -v "$SRC":/src:ro -v $V-git:/git -v $H/.token:/run/t:ro -w /git --entrypoint sh alpine/git:v2.49.1 -c '
    [ -d .git ] || { git init -q -b main . && git config user.name Asha && git config user.email asha@example.com; }
    find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    cp -R /src/. . && git add -A && git commit -qm "$1" && git log --oneline -1
    git push -q "http://asha:$(cat /run/t)@gitea:3000/'$REPO'.git" main 2>&1 | grep -v "^remote:" || true' sh "$3" ;;
wait)   # wait for the newest run to finish, then print its jobs
  for i in {1..180}; do
    s=$(api "/repos/$REPO/actions/runs?limit=1" | docker run --rm -i ghcr.io/jqlang/jq:1.8.1 -r '.workflow_runs[0] | "\(.id) \(.status) \(.conclusion)"')
    [[ $s == *completed* ]] && break; sleep 5; done
  id=${s%% *}; echo "run $s"
  api "/repos/$REPO/actions/runs/$id/jobs" | docker run --rm -i ghcr.io/jqlang/jq:1.8.1 -r '.jobs[] | "\(.id)\t\(.name)\t\(.conclusion)\t\(.started_at[11:19])-\(.completed_at[11:19])"' ;;
logs)   api "/repos/$REPO/actions/jobs/$2/logs" ;;
down)
  docker rm -f $R >/dev/null 2>&1 || true
  for c in $(docker ps -aq --filter name=GITEA-ACTIONS-TASK --filter network=$N); do docker rm -f -v $c >/dev/null; done
  docker rm -f $D $G >/dev/null 2>&1 || true
  for v in gitea-data dind-certs dind-data runner-data git; do docker volume rm $V-$v >/dev/null 2>&1 || true; done
  docker network rm $N >/dev/null 2>&1 || true; rm -f .token; echo lab down ;;
*) sed -n 2,4p $0; exit 1 ;;
esac
