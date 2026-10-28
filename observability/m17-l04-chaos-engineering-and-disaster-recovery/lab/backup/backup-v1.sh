#!/bin/bash
# nightly backup of the catalog database (version 1, the one that "worked" for months)
source ~/bin/backup.env
F=/backups/catalog-$(date +%F).sql.gz
pg_dump catalog 2>>/backups/backup.err | gzip > "$F"
echo "$(date +%T) backup done: $F"
