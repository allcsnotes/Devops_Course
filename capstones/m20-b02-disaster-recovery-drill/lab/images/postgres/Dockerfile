# allcs/postgres:18.6-wal: the official postgres:18.6-alpine3.24 + curl + three scripts:
#   archive-wal.sh   archive_command: every finished WAL file goes to the OFF-SITE bucket (http://bucket:9000/wal/)
#   restore-wal.sh   restore_command: read WAL files back from the bucket during point-in-time recovery
#   dr-entrypoint.sh DB_SOURCE=pitr and an empty volume: fetch the newest base backup from the bucket, then recover
FROM postgres:18.6-alpine3.24
LABEL course=devops
RUN apk add --no-cache curl
COPY archive-wal.sh restore-wal.sh dr-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["dr-entrypoint.sh"]
CMD ["postgres"]
