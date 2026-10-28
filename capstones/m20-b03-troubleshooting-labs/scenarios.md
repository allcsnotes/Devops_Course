# Scenario cards

One card per scenario. Run `./break.sh <n>`, find it with the method, fix it, then `./reset.sh <n>`.
Spoilers below: read a card after you have played it.

## 1 · Bad DNS record
- Symptom: /api/courses answers 503 after 3 s
- First 3: (1) curl https://www.allcsvideos.test/api/courses (2) journalctl -u allcs-api -n 2 (3) dig +short db-01.allcsvideos.test
- Root cause: the db-01 A record points to 10.0.203.21, an old address
- Fix: correct the record, bump the serial, named-checkzone, rndc reload
- Prevention: DNS in git with review; check key names from the servers

## 2 · Full disk
- Symptom: /api/courses answers 500, Errno 28 in the journal
- First 3: (1) journalctl -u allcs-api -n 1 (2) df -h /var/log/allcs (3) du -sh /var/log/allcs/* | sort -h
- Root cause: a forgotten debug log filled the 64 MB log disk
- Fix: lsof (nobody holds it), truncate -s 0, df again
- Prevention: logrotate with maxsize; debug logging that expires; alert at 80%

## 3 · Expired TLS certificate
- Symptom: curl exit 60, certificate has expired
- First 3: (1) curl -sS https://www.allcsvideos.test/api/courses (2) openssl s_client ... | openssl x509 -noout -dates (3) date -u
- Root cause: notAfter passed an hour ago; renewal never ran
- Fix: renew (90 days), nginx -t, systemctl reload nginx
- Prevention: automatic renewal; alert on expiry under 21 days

## 4 · OOMKilled loop
- Symptom: thumbs refuses connections; pod OOMKilled, restarting
- First 3: (1) kubectl get pods (2) kubectl describe pod (Last State) (3) kubectl logs --previous
- Root cause: memory limit 48Mi; the cache alone needs 48 MB
- Fix: limit back to 128Mi (measured peak + headroom)
- Prevention: limits from peak usage; alert on OOM kills and restarts

## 5 · Failing liveness probe
- Symptom: pods restarting every minute; users fine so far
- First 3: (1) kubectl get pods (2) kubectl events --types=Warning (3) kubectl logs deploy/catalog
- Root cause: liveness probe on /health (404); the app serves /healthz
- Fix: patch the probe path, watch restarts stay at 0
- Prevention: test probes with the real image; alert on restart rate

## 6 · Leaked secret
- Symptom: gitleaks finds a password in the last commit
- First 3: (1) git log --oneline -2 (2) gitleaks git --redact -v (3) git show --stat HEAD
- Root cause: the web-01 env file (DB password) was committed
- Fix: rotate FIRST, verify the old one fails, then remove the file
- Prevention: gitleaks pre-commit hook; secrets in a secret store

## 7 · Service selector mismatch
- Symptom: connection refused, but pods Running 1/1
- First 3: (1) kubectl get endpointslices (2) kubectl get svc -o jsonpath (3) kubectl get pods --show-labels
- Root cause: Service selects app=catalog-api; pods are app=catalog
- Fix: patch the selector; endpoints fill
- Prevention: check manifests in CI; alert on zero ready endpoints

## 8 · ImagePullBackOff
- Symptom: rollout stuck; new pod ErrImagePull, old pods serve
- First 3: (1) kubectl rollout status (2) kubectl get pods (3) kubectl events --for pod/...
- Root cause: tag trouble-api:1.0.1 was never built or pushed
- Fix: set the image to a tag that exists (or rollout undo)
- Prevention: deploy only what CI pushed, by digest; gate on rollout status

## 9 · Database connections exhausted
- Symptom: /api/courses answers 503 in 30 ms
- First 3: (1) journalctl -u allcs-api -n 1 (2) psql ... pg_stat_activity (3) SHOW max_connections
- Root cause: nightly-report holds 17 idle connections of 20
- Fix: stop the job; its connections close
- Prevention: pooling (PgBouncer), per-role limits, alert at 80% of max

## 10 · Bad config, rolled back
- Symptom: rollout stuck; new pod CrashLoopBackOff
- First 3: (1) kubectl get pods (2) kubectl logs <new pod> --previous (3) kubectl get configmap v1 v2
- Root cause: config v2 has PAGE_SIZE=2O (letter O); the app exits 1
- Fix: kubectl rollout undo (back to catalog-config-v1)
- Prevention: validate config in CI; versioned config names; keep old versions
