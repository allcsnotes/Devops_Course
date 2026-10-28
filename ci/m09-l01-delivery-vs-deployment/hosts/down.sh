#!/usr/bin/env bash
# down.sh - remove both environment hosts (and everything that ran inside them), the network and the image.
# The deploy keys in keys/ are deleted too: remove the matching GitHub secrets as well.
cd "$(dirname "$0")"
docker rm -f -v staging-01 prod-01 2>/dev/null
docker network rm envs 2>/dev/null
docker rmi env-host 2>/dev/null
rm -rf keys
echo "hosts removed"
