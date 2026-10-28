#!/usr/bin/env bash
# Removes the M05-L01 laptop container and its image (and with them every repository made inside it).
docker rm -f git-laptop 2>/dev/null
docker image rm git-laptop:m05l01 2>/dev/null
echo "M05-L01 lab removed."
