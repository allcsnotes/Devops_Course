#!/bin/sh
# Course Copilot startup: check the config, then hand PID 1 to the real command
set -e
if [ ! -f "$COURSE_INDEX" ]; then
  echo "entrypoint: course index $COURSE_INDEX not found" >&2
  exit 1
fi
echo "entrypoint: Course Copilot $APP_VERSION, index $COURSE_INDEX"
exec "$@"
