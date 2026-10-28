#!/usr/bin/env bash
# The two "staged" moments of the lesson, done from your laptop (outside the container), like in the video.
#   ./lab/stage.sh burst    the debug log grows again: the API writes 20 MB of debug lines at once
#   ./lab/stage.sh inodes   a buggy session cache writes one tiny file per visitor until the inodes run out
set -euo pipefail

case "${1:-}" in
  burst)
    docker exec web-01 curl -s -X POST 'localhost:8080/debug-burst?mb=20' >/dev/null
    echo "Done: api-debug.log just grew by about 20 MB." ;;
  inodes)
    docker exec web-01 bash -c 'install -d -o allcs -g allcs /data/cache;
      runuser -u allcs -- bash -c "i=0; while touch /data/cache/sess-\$i 2>/dev/null; do i=\$((i+1)); done"'
    echo "Done: /data has no free inodes left." ;;
  *)
    echo "usage: $0 burst|inodes" >&2; exit 1 ;;
esac
