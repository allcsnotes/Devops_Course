#!/usr/bin/env bash
# down.sh - removes the users container, prod-01 (with everything inside it), its volume, the network and the image.
cd "$(dirname "$0")"
docker rm -f -v users prod-01 2>/dev/null
docker volume rm prod-01-data 2>/dev/null
docker network rm deploy-lab 2>/dev/null
docker rmi prod-host 2>/dev/null
echo "lab removed (results in ./runs are kept; delete them with: rm -rf runs)"
