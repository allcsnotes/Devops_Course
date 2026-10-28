#!/bin/sh
# first boot only: let the backup agent take base backups (a replication connection), password required
echo "host replication postgres 10.0.202.12/32 scram-sha-256" >> "$PGDATA/pg_hba.conf"
