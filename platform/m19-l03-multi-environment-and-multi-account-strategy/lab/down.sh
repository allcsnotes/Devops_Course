#!/usr/bin/env bash
# down.sh: remove everything the M19-L03 lab created (containers, volumes, network, images, lab tokens).
cd "$(dirname "$0")"
for c in $(docker ps -aq --filter label=lesson=m19-l03); do docker rm -f "$c" >/dev/null; done
# job containers the runner started, and their volumes
for c in $(docker ps -aq --filter network=lab-net --filter name=GITEA-ACTIONS); do docker rm -f -v "$c"; done
for v in $(docker volume ls -q | grep '^GITEA-ACTIONS'); do docker volume rm "$v"; done
for v in $(docker volume ls -q --filter label=lesson=m19-l03); do docker volume rm "$v"; done
docker network rm lab-net 2>/dev/null
docker rmi lab-laptop lab-agent 2>/dev/null
for i in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^localhost:5001/allcsvideos/'); do docker rmi "$i"; done
for i in $(docker images --digests --format '{{.Repository}}@{{.Digest}}' | grep '^localhost:5001/'); do docker rmi "$i"; done
rm -rf secrets
echo "lab down"
