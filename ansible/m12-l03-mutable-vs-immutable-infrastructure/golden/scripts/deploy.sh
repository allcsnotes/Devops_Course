#!/usr/bin/env bash
# deploy.sh VERSION: replace the web instances with new ones. Never patch.
set -euo pipefail
version=${1:?usage: deploy.sh VERSION}
repo=localhost:5000/allcs/web

docker pull -q "$repo:$version" > /dev/null
ref=$(docker image inspect -f '{{index .RepoDigests 0}}' "$repo:$version")
old=$(docker ps -q --filter label=app=web)

echo "== start 2 new instances of $version"
for i in 1 2; do
  docker run -d --name "web-$version-$i" --hostname "web-$version-$i" \
    --network prod --label app=web -e APP_ENV=production "$ref" > /dev/null
done
sleep 1
for i in 1 2; do docker exec "web-$version-$i" curl -fsS localhost/health; done

echo "== switch the load balancer"
printf 'server web-%s-1:80;\nserver web-%s-2:80;\n' "$version" "$version" > upstream.conf
docker cp -q upstream.conf lb:/etc/nginx/upstream.conf
docker exec lb nginx -s reload 2> /dev/null

echo "== remove the old instances"
[ -z "$old" ] || docker rm -f $old > /dev/null
docker ps --filter label=app=web --format '{{.Names}}  {{.Image}}'
