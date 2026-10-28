#!/usr/bin/env bash
# Starts "Asha's laptop" for M05-L01: one container (git-laptop, user asha) with Git 2.43.0,
# the two hc toolkit files this lesson uses in ~/hc, and the Git identity from M01-L03.
# Optional: on Linux (or WSL) with Git and GNU tools you can follow the lesson in your own terminal instead.
set -euo pipefail
cd "$(dirname "$0")"
docker build -t git-laptop:m05l01 .
docker run -d --init --label course=devops-m05l01 --name git-laptop --hostname laptop git-laptop:m05l01 >/dev/null
docker exec git-laptop install -d -o asha -g asha /home/asha/hc /home/asha/hc/conf
docker cp ../hc/README.md       git-laptop:/home/asha/hc/README.md
docker cp ../hc/conf/hc.conf    git-laptop:/home/asha/hc/conf/hc.conf
docker exec git-laptop chown -R asha:asha /home/asha/hc
docker exec -u asha git-laptop sh -c 'git config --global user.name "Asha" && git config --global user.email asha@example.com && git config --global init.defaultBranch main'
echo "Ready. Open it with:  docker exec -it -u asha -w /home/asha git-laptop bash"
