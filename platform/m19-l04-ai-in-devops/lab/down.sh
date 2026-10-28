#!/usr/bin/env bash
# down.sh: remove everything the M19-L04 lab created: the model, the stack, its volumes and images, generated evidence.
cd "$(dirname "$0")"
docker rm -f ai-lab-ollama ai-lab-pull 2>/dev/null; docker network rm ai-lab-ai 2>/dev/null; docker volume rm ai-lab-models 2>/dev/null
docker compose --profile load down -v
docker rmi allcs-catalog-api:1.4.2 allcs-catalog-api:1.5.0 allcs-edge:2.3.0 allcs-edge:2.3.1 allcs-ops:1 2>/dev/null
rm -f incident/*.log runs/*.csv ../incident/*.txt ../incident/*.json ../incident/*.log ../outputs/*.json
echo "lab down"
