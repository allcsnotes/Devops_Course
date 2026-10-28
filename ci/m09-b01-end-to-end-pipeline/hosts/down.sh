#!/usr/bin/env bash
# down.sh - remove both hosts with everything inside them (load balancer, both colours, the data layer and its
# volume), the network, the image and the deploy keys. Remove the matching GitHub secrets as well.
cd "$(dirname "$0")"
docker rm -f -v staging-01 prod-01 2>/dev/null
docker volume rm staging-01-data prod-01-data 2>/dev/null
docker network rm envs 2>/dev/null
docker rmi bg-host 2>/dev/null
rm -rf keys
echo "hosts removed"
