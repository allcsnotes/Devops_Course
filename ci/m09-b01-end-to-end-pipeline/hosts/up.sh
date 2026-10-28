#!/usr/bin/env bash
# up.sh IMAGE_REGISTRY - start the two blue-green environment hosts, staging-01 and prod-01, on THIS Docker machine.
#   IMAGE_REGISTRY  where the images live, e.g. ghcr.io/your-user (packages copilot and storefront; make them public)
# Both hosts come from ONE Dockerfile. Each has its own Docker engine (docker:29.5.3-dind, privileged) running:
#   lb (nginx:1.29.8-alpine) -> blue or green (storefront + Course Copilot), data layer (PostgreSQL 18.6 + Redis 8.10.2),
#   an SSH server where the deploy key may ONLY run deploy-agent, and the deployment record on port 8080.
#
#              SSH (deploy)   load balancer (users)   record (/versions.json)
#   staging-01   2201            8001                    8081
#   prod-01      2202            8002                    8082
#
# GitHub-hosted runners must reach these ports: run it on a machine they can reach (e.g. a small cloud VM). That
# costs money while it runs: stop with down.sh and delete the VM.
set -euo pipefail
cd "$(dirname "$0")"
REG=${1:?usage: up.sh ghcr.io/<owner>}
L=(--label course=devops)
docker build -q "${L[@]}" -t bg-host . >/dev/null
docker network create "${L[@]}" envs >/dev/null 2>&1 || true
mkdir -p keys && chmod 700 keys
start(){ # start NAME HOSTENV SSHPORT LBPORT RECPORT
  local n=$1
  docker run -d "${L[@]}" --privileged --name "$n" --hostname "$n" --network envs \
    -p "$3:22" -p "$4:80" -p "$5:8080" -v "$n-data:/var/lib/docker" -e IMAGE_REGISTRY="$REG" bg-host >/dev/null
  docker cp "$2" "$n:/srv/app/host.env"
  until docker exec "$n" docker info >/dev/null 2>&1; do sleep 1; done
  docker exec "$n" sh -c 'chown deploy:deploy /srv/app/host.env && chmod 644 /srv/app/host.env
    pw=$(head -c 18 /dev/urandom | base64 | tr -dc A-Za-z0-9)   # random per host, never printed
    umask 077; printf "POSTGRES_PASSWORD=%s\n" "$pw" > /srv/app/secrets/postgres.env
    printf "DATABASE_URL=postgresql://allcsvideos:%s@db:5432/allcsvideos\nREDIS_URL=redis://redis:6379/0\n" "$pw" > /srv/app/secrets/db.env
    chown deploy:deploy /srv/app/secrets/*.env'
  # networks, the data layer, and the load balancer (pointing at blue until the first deploy)
  docker exec -u deploy "$n" sh -c 'docker network create --subnet 10.10.1.0/24 edge >/dev/null
    docker network create --internal --subnet 10.10.2.0/24 data >/dev/null
    cd /srv/app && docker compose -f data.yaml up -d --wait >/dev/null 2>&1
    docker run -d --name lb --network edge --ip 10.10.1.2 -p 80:80 --restart unless-stopped --label course=devops \
      -v /srv/lb/conf.d:/etc/nginx/conf.d:ro -v /srv/lb/log:/var/log/nginx nginx:1.29.8-alpine >/dev/null'
  # one deploy key per environment; the public half may only run the deploy agent
  [[ -f keys/$n ]] || ssh-keygen -q -t ed25519 -N '' -C "deploy@$n" -f "keys/$n"
  docker exec -i -u deploy "$n" sh -c 'umask 077; read -r k; printf "restrict,command=\"/usr/local/bin/deploy-agent\" %s\n" "$k" > ~/.ssh/authorized_keys' < "keys/$n.pub"
}
start staging-01 staging-host.env 2201 8001 8081
start prod-01 prod-host.env 2202 8002 8082
echo "hosts up. Private deploy keys (secrets, never commit them): $(pwd)/keys/staging-01 and keys/prod-01"
echo "Host keys for known_hosts (replace localhost with the address GitHub will use):"
ssh-keyscan -t ed25519 -p 2201 localhost 2>/dev/null
ssh-keyscan -t ed25519 -p 2202 localhost 2>/dev/null
