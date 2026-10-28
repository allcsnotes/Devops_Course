#!/usr/bin/env bash
# backup.sh: logical backup of the catalog database that fails loudly
set -euo pipefail                          # any failing command, even inside a pipe, stops the script
source ~/bin/backup.env
F=/backups/catalog-$(date +%Y%m%d-%H%M%S).dump
pg_dump --format=custom --file="$F" catalog  # custom format: compressed, read back with pg_restore
pg_restore --list "$F" > /dev/null           # can the file be read back at all?
echo "$(date +%T) backup ok: $F, $(du -h "$F" | cut -f1)"
