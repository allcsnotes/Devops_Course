#!/bin/sh
# backup-agent.sh: the backup schedule for the allcsvideos production environment (lab timings).
#   every BASE_EVERY s (and once at start): PostgreSQL base backup -> bucket base/<time>/{base,pg_wal}.tar.gz
#   every VAULT_EVERY s: Vault raft snapshot -> bucket vault/vault-<time>.snap   (token: policy "snapshot" only)
# WAL files are NOT shipped here: PostgreSQL's own archive_command sends each finished WAL file (archive-wal.sh).
B=${BUCKET:-http://bucket:9000}; BASE_EVERY=${BASE_EVERY:-21600}; VAULT_EVERY=${VAULT_EVERY:-60}
log(){ echo "$(date '+%H:%M:%S') $*"; }
base_backup(){
  until [ "$(psql -h db -U postgres -d postgres -Atc 'select not pg_is_in_recovery()' 2>/dev/null)" = t ]; do sleep 5; done
  T=$(date +%Y%m%d-%H%M%S); W=/tmp/bb-$T
  if pg_basebackup -h db -U postgres -D $W -Ft -z -X stream -c fast -l "agent $T" >/tmp/bb.log 2>&1 \
     && curl -sf -T $W/base.tar.gz $B/base/$T/base.tar.gz >/dev/null \
     && curl -sf -T $W/pg_wal.tar.gz $B/base/$T/pg_wal.tar.gz >/dev/null \
     && curl -sf -T $W/backup_manifest $B/base/$T/backup_manifest >/dev/null; then
    log "base backup base/$T: $(du -ch $W/*.tar.gz | tail -1 | cut -f1)"
  else log "base backup FAILED: $(tail -1 /tmp/bb.log)"; fi
  rm -rf $W
}
vault_snapshot(){
  T=$(date +%Y%m%d-%H%M%S)
  vault operator raft snapshot save /tmp/v.snap 2>/dev/null && curl -sf -T /tmp/v.snap $B/vault/vault-$T.snap >/dev/null \
    && log "vault snapshot vault/vault-$T.snap" || log "vault snapshot skipped (vault sealed or unreachable)"
  rm -f /tmp/v.snap
}
log "backup agent: base backup every ${BASE_EVERY}s, vault snapshot every ${VAULT_EVERY}s, to $B"
base_backup; last_base=$(date +%s)
while true; do
  vault_snapshot
  sleep $VAULT_EVERY
  [ $(( $(date +%s) - last_base )) -ge $BASE_EVERY ] && { base_backup; last_base=$(date +%s); }
done
