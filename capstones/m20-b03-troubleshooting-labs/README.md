# M20-B03 · Troubleshooting Labs
> Video: Module 20, Build 3. Watch it first, then follow along here.

Ten real production faults on a small copy of allcsvideos: a bad DNS record, a full disk, an expired certificate,
an OOM kill, a failing probe, a leaked secret, a wrong selector, a missing image tag, exhausted database connections
and a bad config. A harness breaks them for real, and one method finds every one.

## What you'll learn
- One eight-step method for any incident: symptom as a user, what changed, layer by layer, hypothesis, test, fix one thing, verify, note.
- The layers: DNS, network, TLS, process, resources (disk, memory, connections), app logs, config.
- The first three commands for each of ten common failures, on a Linux server and in Kubernetes.
- Why order matters in a secret leak: rotate first, clean up second.
- How to time yourself (`note` + `score`) and run this as a Wheel of Misfortune.

## Before you start
- Docker Desktop (recent, with host networking available; the ops box uses `--network host` to reach the kind API)
  and about 2 GB of free memory. Only the `docker` CLI and `bash` run on your laptop.
- Pinned versions (checked 2026-10-21): `ubuntu:24.04` (24.04.5 LTS: nginx 1.24.0, BIND 9.18.39, Python 3.12.3,
  OpenSSL 3.0.13), `postgres:18.6-alpine3.24`, `docker:29.5.3-cli`, kind v0.33.0, `kindest/node:v1.37.0`,
  kubectl v1.37.1, `zricethezav/gitleaks:v8.30.1`, `busybox:1.37.0`, `gcr.io/distroless/python3-debian13` (by digest).
- Background: the site-down walk from module 4, lesson 5; Kubernetes debugging from modules 13-15; gitleaks from module 18.

## Files in this folder
| File | What it is |
|------|------------|
| `lab.sh` | `up`, `status`, `ops` (shell as asha@ops), `sh web01` / `sh ns1`, `down`, `check` |
| `break.sh <1-10>` | Injects one real fault and logs a vague hint, like an alert |
| `reset.sh <1-10\|all>` | Puts it back and prints the status |
| `scenarios.md` | One card per scenario: symptom, first 3 commands, root cause, fix, prevention (spoilers: read after playing) |
| `server/` | Image for web-01 and ns1 (Ubuntu 24.04 + systemd) and their files: nginx site, API, report job, BIND zone, `renew-cert` |
| `db/init.sql` | The `allcs` database (fake course list) |
| `k8s/` | The catalog/thumbs app image, kind config, and the healthy manifests |
| `ops/` | The ops workstation image, plus `note` (timeline line) and `score` (diagnose / fix times) |
| `repo/` | The `allcsvideos-ops` Git repo copied into the ops box: inventory, runbook, nginx and k8s config |

The lab (network `trouble-net`, 10.0.203.0/24):

| Machine | What it is |
|---|---|
| web-01 (10.0.203.10) | nginx with TLS on 443 -> allcs-api (Python, psycopg2); `/var/log/allcs` is a 64 MB disk |
| ns1 (10.0.203.53) | BIND 9, authoritative for `allcsvideos.test` |
| db-01 (10.0.203.20) | PostgreSQL 18.6, `max_connections=20` |
| ops | Asha's workstation: kubectl, kind, curl, dig, openssl, psql, git, gitleaks |
| kind cluster `trouble` | namespace `allcs`: catalog (2 pods + Service), thumbs (1 pod + Service), client |

All passwords in these files are FAKE lab values.

## Follow along
1. Build the lab and check it from the user's side.
   ```bash
   cd capstones/m20-b03-troubleshooting-labs
   bash lab.sh up
   bash lab.sh status
   ```
   ```
   check                              result
   web-01 /api/courses (TLS)          200
   db-01 record (from web-01)         10.0.203.20
   web-01 /var/log/allcs used           1%
   db-01 client connections           1
   pod catalog-799cc88b6b-67t9r       1/1 Running restarts=0
   ...
   ```
2. Open shells. Keep one laptop terminal for `break.sh` / `reset.sh`.
   ```bash
   bash lab.sh ops        # asha@ops
   bash lab.sh sh web01   # asha@web-01
   bash lab.sh sh ns1     # asha@ns1
   ```
3. For every scenario: `bash break.sh N` on the laptop, read the hint, then work the method. Write three notes:
   ```bash
   note "S1 symptom: ..."
   note "S1 cause: ..."
   note "S1 fixed: ..."
   ```
   Then `bash reset.sh N` (the video kept each fix in place; reset is only needed if you did not fix it fully).

### S1 · Hint: "a DNS record changed"
Investigate:
```bash
# ops
curl -s -w ' %{http_code} %{time_total}s\n' https://www.allcsvideos.test/api/courses
# web-01
sudo journalctl -u allcs-api -n 2 --no-pager -o cat
cat /etc/resolv.conf
dig +short db-01.allcsvideos.test
# ops
grep db-01 allcsvideos-ops/inventory/hosts.txt
# ns1
sudo journalctl -u named --no-pager -o short-iso | grep -E "allcsvideos.test/IN: loaded serial" | tail -2
grep -E 'serial|^db-01' /etc/bind/zones/db.allcsvideos.test
```
You should see `503` after about 3 s, and a timeout to `10.0.203.21`.
<details><summary>Cause and fix</summary>

The db-01 A record points to `.21`; the inventory says `.20`. On ns1:
```bash
sudo sed -i -e 's/^db-01 .*/db-01       IN A      10.0.203.20/' -e 's/2026102202  ; serial/2026102203  ; serial/' /etc/bind/zones/db.allcsvideos.test
sudo named-checkzone allcsvideos.test /etc/bind/zones/db.allcsvideos.test
sudo rndc reload allcsvideos.test
```
Then `dig +short db-01.allcsvideos.test` on web-01 says `10.0.203.20`, and the course list answers `200`.
</details>

### S2 · Hint: "debug logging was left on"
Investigate:
```bash
# ops
curl -s -w ' %{http_code} %{time_total}s\n' https://www.allcsvideos.test/api/courses
# web-01
sudo journalctl -u allcs-api -n 1 --no-pager -o cat
df -h /var/log/allcs
sudo du -sh /var/log/allcs/* | sort -h
ls -l /var/log/allcs
sudo head -n 2 /var/log/allcs/api-debug.log
```
You should see `500`, then `[Errno 28] No space left on device` and the disk at `100%`.
<details><summary>Cause and fix</summary>

`api-debug.log` filled the 64 MB log disk. Check nobody holds it open, then truncate (a deleted file that is still
open keeps its space):
```bash
sudo lsof /var/log/allcs/api-debug.log
sudo truncate -s 0 /var/log/allcs/api-debug.log
df -h /var/log/allcs
```
</details>

### S3 · Hint: "the certificate renewal job did not run"
Investigate (ops):
```bash
curl -s -w ' %{http_code} %{time_total}s\n' https://www.allcsvideos.test/api/courses
echo "curl exit code $?"
curl -sS -o /dev/null https://www.allcsvideos.test/api/courses
openssl s_client -connect www.allcsvideos.test:443 -servername www.allcsvideos.test </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
date -u
```
You should see status `000`, `curl exit code 60`, `certificate has expired`.
<details><summary>Cause and fix</summary>

`notAfter` is an hour in the past. On web-01 (`renew-cert` stands in for certbot):
```bash
sudo renew-cert 90
sudo nginx -t
sudo systemctl reload nginx
```
Verify from ops with the `openssl ... -enddate` command and the curl.
</details>

### S4 · Hint: "thumbs memory settings changed"
Wait about 45 s after the break, then (ops):
```bash
kubectl exec client -- wget -qO- -T 3 http://thumbs/healthz
kubectl get pods -l app=thumbs
kubectl describe pod -l app=thumbs | grep -A5 "Last State"
kubectl logs deploy/thumbs --previous
kubectl get deploy thumbs -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
kubectl rollout history deploy/thumbs
```
You should see `Connection refused`, `OOMKilled`, `Exit Code: 137` (128 + 9).
<details><summary>Cause and fix</summary>

Limit 48Mi, but the cache alone is 48 MB plus Python. Thumbs uses `Recreate`, so the old pod was already gone.
```bash
kubectl set resources deploy/thumbs --requests=memory=96Mi --limits=memory=128Mi
kubectl rollout status deploy/thumbs
kubectl get pods -l app=thumbs
kubectl exec client -- wget -qO- -T 3 http://thumbs/healthz
```
</details>

### S5 · Hint: "catalog release with new probe settings"
Wait about 50 s, then (ops):
```bash
kubectl exec client -- sh -c 'for i in $(seq 30); do wget -q -O /dev/null -T 2 http://catalog/courses 2>/dev/null && printf + || printf x; sleep 0.3; done; echo'
kubectl get pods -l app=catalog
kubectl events --types=Warning | tail -4
kubectl logs deploy/catalog | grep 404 | tail -2
kubectl get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet}{"\n"}'
```
Users are fine so far (30 `+`), but each pod has restarted.
<details><summary>Cause and fix</summary>

The liveness probe asks for `/health` (404); the app serves `/healthz`.
```bash
kubectl patch deploy catalog --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/healthz"}]'
kubectl rollout status deploy/catalog
sleep 35; kubectl get pods -l app=catalog
```
</details>

### S6 · Hint: "a commit was pushed to allcsvideos-ops"
Investigate (ops):
```bash
cd allcsvideos-ops
git log --oneline -2
gitleaks git --redact -v --no-banner --no-color
git show --stat --format="%h %an %ad%n%s" HEAD
```
`--redact` keeps the secret off the screen. One finding: `DB_PASSWORD` in `deploy/web-01/api.env`, author Priya.
<details><summary>Cause and fix</summary>

Rotate first (web-01; the new password never appears on screen):
```bash
NEW=$(openssl rand -hex 16)
psql -h db-01.allcsvideos.test -U postgres -d allcs -c "ALTER ROLE allcs_app PASSWORD '$NEW'"
sudo sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$NEW/" /etc/allcs/api.env && unset NEW
sudo systemctl restart allcs-api
```
Prove the leaked one is worthless, then clean up and add a pre-commit hook (ops, in `allcsvideos-ops`):
```bash
curl -s -w ' %{http_code}\n' https://www.allcsvideos.test/api/courses
PGPASSWORD=$(sed -n 's/^DB_PASSWORD=//p' deploy/web-01/api.env) psql -h db-01.allcsvideos.test -U allcs_app -d allcs -c 'select 1'
git rm -q deploy/web-01/api.env && echo "*.env" >> .gitignore && git add .gitignore
git commit -qm "remove web-01 env file, ignore *.env" && git log --oneline -3
gitleaks git --redact --no-banner --no-color; echo "exit $?"
printf '#!/bin/sh\nexec gitleaks git --pre-commit --staged --redact --no-banner --no-color\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
echo "export PGPASSWORD=$(openssl rand -base64 18)" > backup.sh && git add backup.sh
git commit -qm "add backup script"; echo "commit exit $?"
git reset -q backup.sh && rm backup.sh
cd ~
```
`password authentication failed` for the old one; gitleaks still finds it in history (that is why rotation came
first); the hook blocks the test commit with `commit exit 1`.
</details>

### S7 · Hint: "catalog Service updated"
Investigate (ops):
```bash
kubectl exec client -- wget -qO- -T 3 http://catalog/courses
kubectl get pods -l app=catalog
kubectl get endpointslices -l kubernetes.io/service-name=catalog
kubectl get svc catalog -o jsonpath='{.spec.selector}{"\n"}'
kubectl get pods --show-labels -l app=catalog
```
Pods `Running 1/1`, but the endpoint slice is `<unset>`.
<details><summary>Cause and fix</summary>

The Service selects `app=catalog-api`; the pods are labelled `app=catalog`.
```bash
kubectl patch svc catalog -p '{"spec":{"selector":{"app":"catalog"}}}'
kubectl get endpointslices -l kubernetes.io/service-name=catalog
kubectl exec client -- wget -qO- -T 3 http://catalog/courses
```
</details>

### S8 · Hint: "catalog release 1.0.1 deployed"
Wait about 30 s, then (ops):
```bash
kubectl rollout status deploy/catalog --timeout=10s
kubectl get pods -l app=catalog
P=$(kubectl get pods -l app=catalog --field-selector=status.phase=Pending -o name); echo $P
kubectl events --for $P | tail -4
kubectl get deploy catalog -o wide
kubectl rollout history deploy/catalog
```
`ErrImagePull` / `ImagePullBackOff`; the two old pods keep serving.
<details><summary>Cause and fix</summary>

Tag `trouble-api:1.0.1` was never built. Point back at the tag that exists:
```bash
kubectl set image deploy/catalog api=trouble-api:1.0
kubectl rollout status deploy/catalog
```
</details>

### S9 · Hint: "the nightly report job started"
Investigate:
```bash
# ops
curl -s -w ' %{http_code} %{time_total}s\n' https://www.allcsvideos.test/api/courses
# web-01
sudo journalctl -u allcs-api -n 1 --no-pager -o cat
psql -h db-01.allcsvideos.test -U postgres -d allcs -c "SELECT application_name, usename, state, count(*) FROM pg_stat_activity WHERE backend_type = 'client backend' GROUP BY 1, 2, 3 ORDER BY 4 DESC"
psql -h db-01.allcsvideos.test -U postgres -tAc "SHOW max_connections"
systemctl status allcs-report --no-pager | head -4
```
A fast `503` and `remaining connection slots are reserved for roles with the SUPERUSER attribute`.
<details><summary>Cause and fix</summary>

`nightly-report` holds 17 idle connections of 20. Stop the job; its connections close with it:
```bash
sudo systemctl stop allcs-report
psql -h db-01.allcsvideos.test -U postgres -d allcs -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'nightly-report'"
```
</details>

### S10 · Hint: "catalog config v2 rolled out"
Wait about 30 s, then (ops):
```bash
kubectl rollout status deploy/catalog --timeout=10s
kubectl get pods -l app=catalog
P=$(kubectl get pods -l app=catalog --sort-by=.metadata.creationTimestamp -o name | tail -1)
kubectl logs $P --previous
kubectl get deploy catalog -o jsonpath='{..configMapRef.name}{"\n"}'
kubectl get configmap catalog-config-v1 catalog-config-v2 -o custom-columns=NAME:.metadata.name,PAGE_SIZE:.data.PAGE_SIZE
```
`FATAL config: PAGE_SIZE='2O' is not an integer`.
<details><summary>Cause and fix</summary>

That is a capital letter O, not a zero. Each config version has its own name, so the old one is still in the rollout history:
```bash
kubectl rollout undo deploy/catalog
kubectl rollout status deploy/catalog
kubectl get deploy catalog -o jsonpath='{..configMapRef.name}{"\n"}'
```
With Argo CD the lasting fix is a `git revert` of the config commit.
</details>

### The scoreboard
```bash
cat ~/incident/notes.log
score
cat ~/incident/lab.log
```
The video's run: diagnose 2-6 s per scenario (40 s total), fix 105 s total. A script typed those commands and
already knew which ones to run, so they are the floor. Play blind: let a friend run `bash break.sh $((RANDOM % 10 + 1))`.

## Common mistakes
- Changing things before you have a hypothesis. Test without touching first; fix one thing at a time.
- Skipping "what changed?". Nine of these ten began with a change: a record, a limit, a probe, a selector, a tag, a config.
- Deleting a big log file that a process still holds open: the space is not freed. Check `lsof`, then truncate.
- Cleaning up a leaked secret before rotating it. Git history keeps it; only rotation makes it worthless.
- Reading only the status (`ImagePullBackOff`, `CrashLoopBackOff`) and not the message or the previous logs.
- Alerting only on errors. Alert on causes too: certificate expiry under 21 days, disk at 80 %, connections at 80 % of max, restart counts, zero ready endpoints.

## Add your own scenario
One `case` in `break.sh` (the fault and a vague hint), its undo in `reset.sh`, a check in `lab.sh status` if it needs
one, and a card in `scenarios.md`. Ideas from the video: a full inode table, a drifting clock, a network policy that drops traffic.

## Clean up
```bash
bash reset.sh all     # optional: back to healthy
bash lab.sh down
bash lab.sh check     # must print nothing
```

## Next
[M21-L01 · How DevOps Interviews Work](../../interview/m21-l01-how-devops-interviews-work/)
