#!/bin/sh
# dr-entrypoint.sh: DB_SOURCE=init (default) starts PostgreSQL normally (first boot: initdb + the seed scripts).
# DB_SOURCE=pitr on an EMPTY data folder restores instead: the newest base backup from the bucket, then every
# archived WAL file after it (restore_command), then PostgreSQL promotes itself to a normal, writable primary.
set -eu
D=/var/lib/postgresql/18/docker; B=${BUCKET:-http://bucket:9000}
if [ "${DB_SOURCE:-init}" = pitr ] && [ ! -s "$D/PG_VERSION" ]; then
  NEWEST=$(curl -sf "$B/?prefix=base/" | awk '{print $4}' | grep '/base.tar.gz$' | tail -1)
  [ -n "$NEWEST" ] || { echo "dr-entrypoint: no base backup in the bucket" >&2; exit 1; }
  DIR=${NEWEST%/base.tar.gz}
  echo "dr-entrypoint: restoring $DIR from the bucket"
  mkdir -p "$D" && chmod 700 "$D"
  curl -sf "$B/$DIR/base.tar.gz" | tar -xzf - -C "$D"
  mkdir -p "$D/pg_wal" && curl -sf "$B/$DIR/pg_wal.tar.gz" | tar -xzf - -C "$D/pg_wal"
  echo "restore_command = 'restore-wal.sh %f %p'" >> "$D/postgresql.auto.conf"
  touch "$D/recovery.signal"
  chown -R postgres:postgres /var/lib/postgresql
  echo "dr-entrypoint: base backup unpacked, WAL replay starts"
fi
exec docker-entrypoint.sh "$@"
