#!/usr/bin/env bash
# up.sh - the M09-L02 lab: prod-01, a "server" with its own Docker engine (docker:29.5.3-dind, privileged), on the
# Docker network deploy-lab (10.0.92.0/24). Inside prod-01:
#   network "prod" 10.0.93.0/24 (exists only inside prod-01)
#   lb           nginx:1.29.8-alpine, port 80 of prod-01 (published on your laptop as http://localhost:8080)
#   blue-1..3    10.0.93.11-13   Course Copilot instances (start on 1.6.0)
#   green-1..3   10.0.93.21-23   the second pool (blue-green and canary)
#   images copilot:1.6.0, copilot:1.7.0 and copilot:1.7.1 (a bad build, staged on purpose), built inside prod-01
# You work inside prod-01 as user asha:  docker exec -it -u asha -w /home/asha/deploy prod-01 bash
set -euo pipefail
cd "$(dirname "$0")"
L=(--label course=devops)
docker network create "${L[@]}" --subnet 10.0.92.0/24 deploy-lab >/dev/null
docker volume create "${L[@]}" prod-01-data >/dev/null
docker build -q "${L[@]}" -t prod-host host >/dev/null
docker run -d "${L[@]}" --name prod-01 --hostname prod-01 --network deploy-lab --ip 10.0.92.10 --network-alias prod-01 \
  --privileged -p 127.0.0.1:8080:80 -v prod-01-data:/var/lib/docker prod-host >/dev/null
until docker exec prod-01 docker info >/dev/null 2>&1; do sleep 1; done
docker cp app prod-01:/srv/app-src
for v in 1.6.0 1.7.0 1.7.1; do
  echo "building copilot:$v inside prod-01"
  docker exec prod-01 docker build -q --build-arg APP_VERSION=$v -t copilot:$v /srv/app-src >/dev/null
done
docker cp deploy prod-01:/home/asha/deploy
docker cp lb/site.conf prod-01:/srv/lb/conf.d/site.conf
docker exec prod-01 sh -c 'echo "map \$host \$pool { default blue; }" > /srv/lb/conf.d/route.conf && chown -R asha:asha /home/asha/deploy /srv/lb'
docker exec prod-01 docker network create --subnet 10.0.93.0/24 prod >/dev/null
docker exec -u asha prod-01 bash -c 'source ~/deploy/lib.sh; for n in blue-1 blue-2 blue-3; do start_app $n 1.6.0; pool_add blue $n; done; lb_render'
docker exec prod-01 docker run -d --name lb --network prod --ip 10.0.93.2 -p 80:80 --label course=devops \
  -v /srv/lb/conf.d:/etc/nginx/conf.d:ro -v /srv/lb/log:/var/log/nginx nginx:1.29.8-alpine >/dev/null
docker exec -u asha prod-01 bash -c 'cd ~/deploy && ./reset.sh 1.6.0'
echo "lab up: http://localhost:8080"
