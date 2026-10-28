#!/usr/bin/env bash
# Removes everything up.sh created: five containers, two networks, two images.
set -uo pipefail
docker rm -f laptop priya-laptop bastion web-01 db-01 2>/dev/null
docker network rm ssh-public ssh-private 2>/dev/null
docker rmi ssh-lab-db:1 ssh-lab-sshd:1 2>/dev/null
echo "SSH lab removed."
