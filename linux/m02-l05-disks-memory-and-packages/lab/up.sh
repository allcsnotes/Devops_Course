#!/usr/bin/env bash
# Builds the lab image and starts the "web-01" server.
#  --tmpfs /data ...      web-01's small data disk: a real 64 MB tmpfs with 4096 inodes, so filling it is safe
#  --cap-add SYS_PTRACE   lets root see other users' open files (/proc/<pid>/fd), as on a normal server: lsof needs it
# Then log in as asha with:   docker exec -it web-01 su - asha
set -euo pipefail
cd "$(dirname "$0")"

docker build -t disk-lab:1 .
docker rm -f web-01 >/dev/null 2>&1 || true
docker run -d --name web-01 --hostname web-01 --cap-add SYS_PTRACE \
  --tmpfs /data:rw,size=64m,nr_inodes=4096,mode=755 disk-lab:1

echo "Waiting for the data disk to fill up and the API to start..."
for _ in $(seq 1 60); do
  docker exec web-01 pgrep -x python3 >/dev/null 2>&1 && break
  sleep 1
done
docker exec web-01 df -h /data
echo
echo "web-01 is running. Log in as asha with:"
echo "  docker exec -it web-01 su - asha"
echo "(sudo password for asha in this lab: demo-password-123)"
