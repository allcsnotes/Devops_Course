#!/bin/sh
# restore-wal.sh <file name> <path>: PostgreSQL's restore_command. A missing file (404) ends recovery: that's normal.
exec curl -sf --max-time 20 -o "$2" "${BUCKET:-http://bucket:9000}/wal/$1"
