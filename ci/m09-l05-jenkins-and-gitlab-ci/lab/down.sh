#!/usr/bin/env bash
# down.sh - removes every lab container, all lab volumes, the network and the three lab images.
docker rm -f -v jenkins-agent jenkins cicd-laptop cicd-docker cicd-gitea 2>/dev/null
for v in gitea-data dind-certs dind-data agent-work asha-work jenkins-home jenkins-secrets; do docker volume rm cicd-$v 2>/dev/null; done
docker network rm cicd-lab 2>/dev/null
docker rmi cicd-jenkins cicd-agent cicd-laptop 2>/dev/null
echo "lab removed"
