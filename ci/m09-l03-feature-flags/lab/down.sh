#!/usr/bin/env bash
# down.sh - removes every container, the flag volume, the network and the three lab images.
docker rm -f traffic lb copilot-1 copilot-2 copilot-3 model flagd web-01 2>/dev/null
docker volume rm flags-data 2>/dev/null
docker network rm flags-lab 2>/dev/null
docker rmi flags-web01 flags-model flags-copilot flags-copilot-test 2>/dev/null
echo "lab removed (traffic results in ./runs are kept)"
