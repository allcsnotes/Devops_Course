#!/bin/bash
# down.sh: remove the web-01 container and its image
docker rm -f web-01 >/dev/null 2>&1 || true
docker rmi web-01:1.0 >/dev/null 2>&1 || true
echo "removed web-01"
