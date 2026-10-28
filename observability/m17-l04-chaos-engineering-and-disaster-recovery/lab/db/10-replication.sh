#!/bin/sh
# allow pg_basebackup from the backup host (a replication connection), password required
echo "host replication allcs all scram-sha-256" >> "$PGDATA/pg_hba.conf"
