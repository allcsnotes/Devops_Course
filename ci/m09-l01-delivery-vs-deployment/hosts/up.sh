#!/usr/bin/env bash
# up.sh IMAGE_REPO - start the two environment hosts, staging-01 and prod-01, on THIS Docker machine.
#   IMAGE_REPO  where the hosts pull Course Copilot from, e.g. ghcr.io/your-user/course-copilot (make the GHCR package
#               public, or the hosts cannot pull it)
# Both hosts are built from the ONE Dockerfile in this folder (environment parity); only app.env differs.
# Each host: its own Docker engine (docker:29.5.3-dind, privileged as Docker-in-Docker needs), an SSH server where the
# deploy key may ONLY run deploy-agent (forced command), and the deployment record on port 8080.
#
#              SSH (deploy)   app (/health, /version)   record (/versions.json)
#   staging-01   2201            8001                      8081
#   prod-01      2202            8002                      8082
#
# For GitHub-hosted runners to reach the hosts, run this on a machine they can reach (for example a small cloud VM
# with those ports open to the internet). That costs money while it runs: stop it with down.sh and delete the VM.
# On your laptop it is free, and you can drive the deploy agent by hand (see the lesson README).
set -euo pipefail
cd "$(dirname "$0")"
IMAGE_REPO=${1:?usage: up.sh ghcr.io/<owner>/course-copilot}
L=(--label course=devops)
docker build -q "${L[@]}" -t env-host . >/dev/null
docker network create "${L[@]}" envs >/dev/null 2>&1 || true
mkdir -p keys && chmod 700 keys
start(){ # start NAME ENVFILE SSHPORT APPPORT RECPORT
  local n=$1 env=$2
  docker run -d "${L[@]}" --privileged --name "$n" --hostname "$n" --network envs \
    -p "$3:22" -p "$4:8000" -p "$5:8080" -e IMAGE_REPO="$IMAGE_REPO" env-host >/dev/null
  docker cp "$env" "$n:/srv/app/app.env"
  docker exec "$n" chown deploy:deploy /srv/app/app.env
  # one deploy key per environment; the public half may only run the deploy agent
  [[ -f keys/$n ]] || ssh-keygen -q -t ed25519 -N '' -C "deploy@$n" -f "keys/$n"
  docker exec -i -u deploy "$n" sh -c 'umask 077; read -r k; printf "restrict,command=\"/usr/local/bin/deploy-agent\" %s\n" "$k" > ~/.ssh/authorized_keys' < "keys/$n.pub"
}
start staging-01 staging.env 2201 8001 8081
start prod-01 production.env 2202 8002 8082
for n in staging-01 prod-01; do
  until docker exec "$n" docker info >/dev/null 2>&1; do sleep 1; done
done
echo "hosts up. Private deploy keys (secrets, never commit them): $(pwd)/keys/staging-01 and keys/prod-01"
echo "Host keys for known_hosts (replace localhost with the address GitHub will use):"
ssh-keyscan -t ed25519 -p 2201 localhost 2>/dev/null
ssh-keyscan -t ed25519 -p 2202 localhost 2>/dev/null
