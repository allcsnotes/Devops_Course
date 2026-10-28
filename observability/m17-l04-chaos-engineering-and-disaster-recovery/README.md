# M17-L04 · Chaos Engineering and Disaster Recovery
> Video: Module 17, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- Chaos engineering as a controlled experiment: steady state from your SLIs, a hypothesis, one fault, an abort line, rollback.
- Running four real experiments (kill a replica, network delay, packet loss, database down) and reading the findings.
- Backups that fail loudly, restore tests, and point-in-time recovery (PITR) with a base backup plus archived WAL.
- A disaster recovery drill with a clock: measuring the real RTO and RPO.
- DR strategies (backup and restore, pilot light, warm standby, multi-site), multi-AZ vs multi-region, and game days.

## Before you start
- Docker Desktop (Compose v2), `curl`, `jq`, `bash`.
- [M17-L01](../m17-l01-slis-slos-and-error-budgets/) (SLIs and the 14.4x burn-rate line used as the abort condition).
- Free ports 8080 (nginx in front of the API), 9090 (Prometheus), 3000 (Grafana).
- Images used (pinned): `postgres:18.6-alpine3.24`, `nginx:1.29.8-alpine`, `prom/prometheus:v3.15.0`, `grafana/grafana:13.2.4`;
  the API and the backup host are built from `lab/app/` and `lab/backup/`.

## Files in this folder
| File | What it is |
|---|---|
| `lab/up.sh`, `lab/down.sh` | Start the lab (and load 1,000,000 fake enrollments); remove everything it created |
| `lab/compose.yaml` | Postgres with WAL archiving, `api1` + `api2` (with `NET_ADMIN` for `tc`), nginx `lb`, `students` (20 req/s), Prometheus, Grafana, the `backup` host, and `db-test` / `db-pitr` |
| `lab/app/` | The API (`api.py`: stale course list if the DB is down) and the load generator (`loadgen.py`, logs every confirmed enrollment to `data/acks.csv`) |
| `lab/nginx/nginx.conf` | Two replicas, passive health checks, retry GETs on another replica, 2 s read timeout |
| `lab/prometheus/sli.yml` | The SLIs over a 30 s window: availability and p99 latency, measured from the students' side |
| `lab/chaos/chaos.sh` | Runs ONE experiment: checks steady state, injects, watches every 5 s, aborts above 1.44 % errors or p99 500 ms, always rolls back |
| `lab/chaos/experiments/*.sh` | `kill-replica`, `latency`, `packet-loss`, `db-down`: a hypothesis, a duration, `inject` and `rollback` |
| `lab/backup/backup-v1.sh` | The old silent nightly job (the hook) |
| `lab/backup/backup.sh` | The fixed job: `set -euo pipefail`, `pg_dump` custom format, read back with `pg_restore --list` |
| `lab/backup/restore-test.sh` | Restores the newest dump into the empty `db-test` and compares row counts with the live DB |
| `lab/backup/backup.env` | The backup job's credentials (fake lab password) |
| `lab/dr/dr-restore.sh` | The DR runbook, automated: empty Postgres, restore beside it, check, switch, smoke test |
| `lab/backup/dr-report.sh` | Measures RPO and RTO of a drill against what the students were told was saved |
| `lab/grafana/` | Dashboard **allcsvideos · SLIs during chaos experiments** |

You will use two shells: your **laptop** shell in `lab/`, and a shell on the **backup host**:
```bash
docker compose exec backup bash
export PATH=$PATH:$HOME/bin PGPASSWORD=demo-password-123    # fake lab password
```

## Follow along
1. Start the lab.
   ```bash
   cd lab
   ./up.sh
   ```
   You should see `api1`, `api2`, `backup`, `db`, `db-test`, `grafana`, `lb`, `prometheus` and `students` up.
   Grafana: http://localhost:3000 (user `admin`, password `fake-admin-pass-123`, fake lab password).

2. **The hook: a backup that "worked".** Stage the password rotation the job was never told about, on the laptop:
   ```bash
   sed -i.bak 's/demo-password-123/demo-password-122/' backup/backup.env
   ```
   Then on the backup host:
   ```bash
   backup-v1.sh
   echo "exit code $?"
   ls -l /backups
   createdb -h db-test catalog
   gunzip -c /backups/catalog-*.sql.gz | psql -h db-test catalog
   psql -h db-test catalog -c "SELECT count(*) FROM enrollments"
   gunzip -c /backups/catalog-*.sql.gz | wc -c
   cat /backups/backup.err
   ```
   ```
   21:51:27 backup done: /backups/catalog-2026-10-21.sql.gz
   exit code 0
   -rw-r--r-- 1 root root  20 Oct 21 21:51 catalog-2026-10-21.sql.gz
   ERROR:  relation "enrollments" does not exist
   0
   pg_dump: error: connection to server at "db" ..., port 5432 failed: FATAL:  password authentication failed for user "allcs"
   ```

3. **Experiment 1: kill a replica** (laptop).
   ```bash
   ./chaos/chaos.sh kill-replica
   ```
   ```
   21:51:40 steady state: errors 0.00%  p99 10 ms
   21:51:40 hypothesis: with api1 killed, the load balancer keeps errors under 0.1% and p99 under 250 ms
   ...
   21:52:11   +30s  errors 0.00%  p99 67 ms
   RESULT: hypothesis held (worst: errors 0%, p99 67 ms)
   ```
   On the dashboard api2 takes all 20 requests a second; nginx retried on the other replica.

4. **Experiment 2: 100 ms network delay on api2.**
   ```bash
   docker compose exec -u 0 api2 tc qdisc show dev eth0
   ./chaos/chaos.sh latency
   ```
   ```
   21:53:12   +5s  errors 0.00%  p99 25 ms
   21:53:17 ABORT: errors 0.00%  p99 805 ms  (limit 1.44% / 500 ms)
   21:53:17 rollback: netem removed from api2
   RESULT: hypothesis disproved (worst: errors 0%, p99 805 ms, aborted: yes)
   ```
   100 ms became 805: each replica has one database connection, and every query paid the delay, so queries queued.
   Finding: a connection pool, and a timeout on every call.

5. **Experiment 3: 30 % packet loss on api2.**
   ```bash
   ./chaos/chaos.sh packet-loss
   ```
   Nothing fails (lost packets are resent), but p99 climbs to 450 ms, then 1714 ms: ABORT, 16 seconds in.

6. **Experiment 4: stop the database.** In one laptop terminal start the experiment; in a second one, ask the API
   while it runs:
   ```bash
   ./chaos/chaos.sh db-down
   ```
   ```bash
   curl -s -i localhost:8080/api/courses | grep -E 'HTTP|Stale|courses'
   curl -s -w ' %{http_code} %{time_total}s\n' -X POST -d '{"course_id": 3}' localhost:8080/api/enroll
   ```
   ```
   HTTP/1.1 200 OK
   X-Stale: true
   {"error": "database unavailable", ...}
    503 0.046390s
   ...
   21:56:35 ABORT: errors 3.06%  p99 1600 ms  (limit 1.44% / 500 ms)
   ```
   Reads degraded as designed; writes failed, and stale reads were slow. Finding: fail fast (a circuit breaker).

7. **A backup that fails loudly.** On the backup host, with the wrong password still in place:
   ```bash
   backup.sh
   echo "exit code $?"
   ```
   ```
   pg_dump: error: connection to server at "db" ..., port 5432 failed: FATAL:  password authentication failed for user "allcs"
   exit code 1
   ```
   Fix the password on the laptop (`mv backup/backup.env.bak backup/backup.env`), then on the backup host:
   ```bash
   backup.sh
   ls -lh /backups
   restore-test.sh
   ```
   ```
   21:59:11 backup ok: /backups/catalog-20261021-215911.dump, 8.3M
   -rw-r--r-- 1 root root    0 Oct 21 21:59 catalog-20261021-215909.dump
   restored: 1000944 enrollments, 40 courses, newest row 2026-10-21 21:59:11.07316+05:30
   live db, rows up to that moment: 1000944
   RESTORE TEST PASSED in 1.2 s
   ```
   The failed run left an empty file behind: trust the exit code, not the file.

8. **Point-in-time recovery.** On the backup host: a base backup, then the staged accident (note the time it prints).
   ```bash
   pg_basebackup -D /backups/base -Ft -z -X stream -c fast
   ls -lh /backups/base
   ls /archive | tail -4
   psql -Atc "SELECT count(*) FROM enrollments WHERE course_id = 7"
   date '+%F %T.%3N'
   psql -c "DELETE FROM enrollments WHERE course_id = 7"
   ```
   Prepare a recovery server from the base backup, stopping just before the delete. Replace `<TIME>` with the time
   `date` printed (for example `2026-10-21 21:59:57.719`):
   ```bash
   mkdir -p /restore/18/docker && cd /restore/18/docker
   tar -xzf /backups/base/base.tar.gz && tar -xzf /backups/base/pg_wal.tar.gz -C pg_wal
   echo "restore_command = 'cp /archive/%f %p'" >> postgresql.auto.conf
   echo "recovery_target_time = '<TIME>+05:30'" >> postgresql.auto.conf
   echo "recovery_target_action = 'promote'" >> postgresql.auto.conf
   touch recovery.signal && cd
   ```
   Start it from the laptop and read its log:
   ```bash
   time docker compose --profile pitr up -d --wait db-pitr
   docker compose logs db-pitr | grep -E 'redo starts|recovery stopping|last completed|archive recovery complete' | cut -c 12-
   ```
   ```
   LOG:  recovery stopping before commit of transaction 1807, time 2026-10-21 21:59:58.072166+05:30
   LOG:  last completed transaction was at log time 2026-10-21 21:59:57.575373+05:30
   LOG:  archive recovery complete
   ```
   Copy the lost rows back into production (backup host):
   ```bash
   psql -h db-pitr -Atc "SELECT count(*) FROM enrollments WHERE course_id = 7"
   psql -h db-pitr -c "\copy (SELECT * FROM enrollments WHERE course_id = 7) TO STDOUT" | psql -c "\copy enrollments FROM STDIN"
   psql -Atc "SELECT count(*) FROM enrollments WHERE course_id = 7"
   ```
   `COPY 25031`, and production now has 25,033: every lost row plus two made after the accident.

9. **The DR drill, with a clock.** Fresh backup (backup host), wait a minute while the students keep enrolling:
   ```bash
   backup.sh
   ```
   The staged disaster: the database and its disk are gone (laptop). Note the time it prints.
   ```bash
   date +%T.%3N; docker compose rm -s -f db; docker volume rm chaos-lab_pgdata
   curl -s localhost:8080/api/courses
   curl -s -X POST -d '{"course_id": 3}' localhost:8080/api/enroll
   ```
   Run the runbook:
   ```bash
   time ./dr/dr-restore.sh
   ```
   ```
   22:02:11 1. start an empty PostgreSQL
   22:02:27 2. restore the newest dump beside it, into catalog_new
   22:02:30 3. check it before anyone uses it
      1001129 enrollments, newest 2026-10-21 22:00:43.573406+05:30
   22:02:30 4. switch: the restored database becomes catalog
   22:02:31 5. smoke test through the load balancer
   real	0m20.226s
   ```

10. Measure RPO and RTO (backup host), using the disaster time from step 9:
    ```bash
    dr-report.sh <HH:MM:SS.mmm>
    ```
    ```
    disaster:                    22:01:45.709
    newest row in the backup:    22:00:43.573
    data lost (RPO):             62 s, 125 confirmed enrollments
    first enrollment saved again: 22:02:31.579
    enrollments down (RTO):      46 s
    ```
    Lost ids can come back as duplicates. Look for an id that was confirmed twice:
    ```bash
    cut -d, -f2 /acks/acks.csv | sort | uniq -d | head
    ```
    In the video, enrollment 1001131 was given out at 22:00:44, lost, and given out again at 22:02:31.

## Key ideas
| DR strategy | RPO | RTO |
|---|---|---|
| Backup and restore | hours | 24 hours or less |
| Pilot light | minutes | tens of minutes |
| Warm standby | seconds | minutes |
| Multi-site active-active | near zero | potentially zero |

Multi-AZ (e.g. RDS Multi-AZ, synchronous standby, failover typically 60-120 s) protects against a lost zone, not a bad
`DELETE`. Multi-region replication is asynchronous, so a region failover can lose the last seconds.

## Common mistakes
- **Untested backups.** Exit code 0 and 20 bytes. Only a restore proves a backup.
- **Backups in the same blast radius.** This lab keeps them on the same laptop as the database. Copy them away, and lock
  some copies against deletion (3-2-1 rule; replicas don't count).
- **Chaos without an abort line.** Every failed experiment here stopped within 16 seconds because the line was written first.
- **Chaos in production before staging.** The netem experiment found a queue in minutes; find that in staging.

## Clean up
```bash
./down.sh
rm -f backup/backup.env.bak
```

## Next
[M17-B01 · Game Day with SLOs, Chaos and a Postmortem](../m17-b01-game-day-with-slos-chaos-and-a-postmortem/)
