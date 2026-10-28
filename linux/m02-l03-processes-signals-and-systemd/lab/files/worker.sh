#!/bin/bash
# allcsvideos upload worker (demo): holds a lock file while it runs
LOCK=/tmp/upload-worker.lock
if [ -e "$LOCK" ]; then
  echo "worker: lock file exists, is another worker running? exiting"
  exit 1
fi
cleanup() {
  echo "worker: got SIGTERM, removing the lock file"
  rm -f "$LOCK"
  exit 0
}
trap cleanup TERM
echo $$ > "$LOCK"
echo "worker: started, PID $$"
while true; do sleep 1; done
