#!/usr/bin/env bash
# Removes the M05-L03 lab container (and with it every repository inside) and its image.
docker rm -f git-team 2>/dev/null
docker image rm git-team:m05l03 2>/dev/null
echo "M05-L03 lab removed."
