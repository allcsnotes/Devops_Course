#!/usr/bin/env bash
# down.sh - removes the token service and Vault (then run the Gitea lab's own down.sh if you are done with it).
docker rm -f token-service vault 2>/dev/null
docker rmi lab-token-service 2>/dev/null
echo "oidc lab removed"
