# allcs/backup-agent:1.0: runs inside the production environment and ships backups OFF-SITE to the bucket.
#   PostgreSQL base backups (pg_basebackup from postgresql18-client 18.6) and Vault raft snapshots (vault CLI 2.1.2)
FROM hashicorp/vault:2.1.2
LABEL course=devops
USER root
RUN apk add --no-cache curl postgresql18-client tzdata
COPY backup-agent.sh /usr/local/bin/
USER vault
ENTRYPOINT ["backup-agent.sh"]
