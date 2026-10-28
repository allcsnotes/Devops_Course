#!/usr/bin/env bash
# down.sh - removes only what this lab created: Backstage, the runner, its job containers, Gitea, volumes, network,
# the portal image and the lab tokens. The portal source folder you generated is left alone (delete it yourself).
set -uo pipefail
cd "$(dirname "$0")"
docker rm -f backstage gitea-runner 2>/dev/null
# job / step containers that the runner started on THIS lab's network
for c in $(docker ps -aq --filter network=idp-net --filter name=GITEA-ACTIONS); do
  vols=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "$c" | tr ' ' '\n' | grep '^GITEA-ACTIONS')
  docker rm -f -v "$c"; for v in $vols; do docker volume rm "$v" 2>/dev/null; done
done
docker rm -f -v gitea 2>/dev/null
for v in $(docker volume ls -q --filter label=lab=idp); do docker volume rm "$v"; done
docker network rm idp-net 2>/dev/null
docker rmi allcsvideos-portal:1.0 2>/dev/null
rm -rf secrets
echo "lab removed"
