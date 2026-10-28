#!/usr/bin/env bash
# ai.sh pull|up|down: the small local model for the lab. Ollama 0.40.6 (CPU only: Docker on a Mac has no GPU),
# model llama3.2:3b (Q4_K_M, 2.0 GB, Llama 3.2 Community License). The server sits on an INTERNAL Docker network:
# no route to the internet, so no lab data can leave this machine. Cloud models are switched off as well.
# Needs: 4 CPUs and 4 GB of memory for Docker, about 2 GB of disk for the model.
set -euo pipefail
IMG=ollama/ollama:0.40.6
case ${1:-} in
  pull)  # the only step with internet: download the model into a named volume, then throw the container away
    docker volume create --label course=devops --label lesson=m19-l04 ai-lab-models
    docker run -d --name ai-lab-pull --label course=devops -v ai-lab-models:/root/.ollama $IMG
    docker exec ai-lab-pull ollama pull llama3.2:3b
    docker rm -f ai-lab-pull ;;
  up)
    docker network create --internal --label course=devops --label lesson=m19-l04 ai-lab-ai
    docker run -d --name ai-lab-ollama --label course=devops --label lesson=m19-l04 --hostname ollama --network ai-lab-ai \
      --memory 4g --memory-swap 4g --cpus 4 -e OLLAMA_NO_CLOUD=1 -e OLLAMA_KEEP_ALIVE=30m \
      -v ai-lab-models:/root/.ollama $IMG
    docker network connect ai-lab-ai ai-lab-ops ;;   # the ops box reaches the model; nothing else does
  down)
    docker rm -f ai-lab-ollama; docker network rm ai-lab-ai; docker volume rm ai-lab-models ;;
  *) echo "usage: $0 pull|up|down"; exit 1 ;;
esac
