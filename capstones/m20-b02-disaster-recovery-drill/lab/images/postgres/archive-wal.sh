#!/bin/sh
# archive-wal.sh <path> <file name>: PostgreSQL's archive_command. Exit 0 only when the bucket has the file.
# The bucket answers 201 (stored) or 200 (already there, same bytes); 409 (different bytes) is a failure.
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -T "$1" "${BUCKET:-http://bucket:9000}/wal/$2")
[ "$code" = 201 ] || [ "$code" = 200 ]
