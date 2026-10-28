#!/usr/bin/env bash
# stage.sh <step> - makes the teammates' commits that happen off screen in the video, in the right clone, as the right user.
#   rahul-logrotate  Rahul pushes a logrotate change to main                                        (before step 3)
#   wednesday        Asha's branch tune/disk-thresholds (CRIT 95), Priya's WARN 85 on main, Asha's CERT_DAYS 30,
#                    Rahul's README fix and his "checks: simplify rate()" (the bug bisect finds), Priya's test tweak (step 4)
#   shared-branch    the shared branch feature/notify-v2 (Priya + Asha, pushed), Priya's local unpushed commit on it,
#                    and Rahul's timer fix on main                                                    (step 7)
#   spike            Asha's spike/json-alerts branch with two commits                                 (step 9)
#   two-commits      Asha's "CRIT at load 4" and "experiment: also check /tmp" commits on main         (step 11)
#   demo-conflict    two scratch branches demo-a / demo-b that conflict on MEM_WARN                   (step 14)
set -euo pipefail
as() { docker exec -i -u "$1" -w "/home/$1/allcsvideos-ops" git-team bash -se; }
case "${1:-}" in
rahul-logrotate) as rahul <<'EOF'
git pull -q && sed -i 's/^    rotate 14$/    rotate 14\n    maxsize 50M/' hc/logrotate/hc && git commit -qam 'logrotate: also rotate at 50 MB' && git push -q
EOF
;;
wednesday)
as asha <<'EOF'
git switch -q -c tune/disk-thresholds && sed -i 's/^DISK_CRIT=90$/DISK_CRIT=95/' hc/hc.conf && git commit -qam 'hc.conf: CRIT at 95% disk (the 2 TB data volume)' && git switch -q main
EOF
as priya <<'EOF'
git pull -q && sed -i 's/^DISK_WARN=75$/DISK_WARN=85/' hc/hc.conf && git commit -qam 'hc.conf: warn at 85% disk (fewer alerts from /data)' && git push -q
EOF
as asha <<'EOF'
git pull -q && sed -i 's/^CERT_DAYS=14$/CERT_DAYS=30/' hc/hc.conf && git commit -qam 'hc.conf: CERT_DAYS 30 (renew 30 days before expiry)' && git push -q
EOF
as rahul <<'EOF'
git pull -q && sed -i 's|^tests/run.sh         plain Bash test runner (+ three test configs)$|tests/run.sh         plain Bash test runner (+ four test configs)|' hc/README.md && git commit -qam 'README: four test configs now' && git push -q
git pull -q && sed -i 's/^  if (( $1 >= $3 )); then echo CRIT$/  if (( $1 > $3 )); then echo CRIT/; s/^  elif (( $1 >= $2 )); then echo WARN$/  elif (( $1 > $2 )); then echo WARN/' hc/lib/checks.sh && git commit -qam 'checks: simplify rate()' && git push -q
EOF
as priya <<'EOF'
git pull -q && sed -i 's/^HTTP_TIMEOUT=1$/HTTP_TIMEOUT=2/' hc/tests/warn.conf && git commit -qam 'tests: 2 second HTTP timeout in warn.conf' && git push -q
EOF
;;
shared-branch)
as priya <<'EOF'
git switch -q main && git pull -q && git switch -q -c feature/notify-v2
perl -0pi -e 's/^    echo "hc: NOTIFY_V2 is not ready yet" >&2; return 1\n/    python3 "\$lib\/report.py" alert "\${WEBHOOK_URL%\/hc}\/hc-\$2" "\$1" "\$2" <<< "\$results"; return\n/m' hc/bin/hc
git commit -qam 'notify: per-severity webhook paths behind NOTIFY_V2' && git push -q -u origin feature/notify-v2
EOF
as asha <<'EOF'
git fetch -q && git switch -q feature/notify-v2 && printf '\nNOTIFY_V2=on: WARN and CRIT alerts go to separate webhook paths (in progress).\n' >> hc/README.md && git commit -qam 'README: document NOTIFY_V2' && git push -q && git switch -q main
EOF
as priya <<'EOF'
git switch -q feature/notify-v2 && git pull -q && cp hc/tests/ok.conf hc/tests/v2.conf && sed -i 's/^NOTIFY_V2=off$/NOTIFY_V2=on/' hc/tests/v2.conf && git add hc/tests/v2.conf && git commit -qm 'tests: a config with NOTIFY_V2=on'
EOF
as rahul <<'EOF'
git switch -q main && git pull -q && sed -i 's/^RandomizedDelaySec=20s$/RandomizedDelaySec=20s\nPersistent=true/' hc/systemd/hc.timer && git commit -qam 'timer: catch up missed runs after downtime (Persistent=true)' && git push -q
EOF
;;
spike) as asha <<'EOF'
git switch -q -c spike/json-alerts main && printf '# spike: write each hc result as one JSON line\n' > hc/lib/jsonl.py && git add hc/lib/jsonl.py && git commit -qm 'spike: JSON lines output' && echo 'import json' >> hc/lib/jsonl.py && git commit -qam 'spike: import json' && git switch -q main
EOF
;;
two-commits) as asha <<'EOF'
sed -i 's/^LOAD_CRIT=3$/LOAD_CRIT=4/' hc/hc.conf && git commit -qam 'hc.conf: CRIT at load 4 per CPU'
sed -i 's|^MOUNTS=.*|MOUNTS=/ /data /var/log /tmp|' hc/hc.conf && git commit -qam 'experiment: also check /tmp'
EOF
;;
demo-conflict) as asha <<'EOF'
git switch -q -c demo-a && sed -i 's/^MEM_WARN=15$/MEM_WARN=25/' hc/hc.conf && git commit -qam 'demo: MEM_WARN 25' && git switch -q -c demo-b main && sed -i 's/^MEM_WARN=15$/MEM_WARN=10/' hc/hc.conf && git commit -qam 'demo: MEM_WARN 10' && git switch -q demo-a
EOF
;;
*) sed -n '2,11p' "$0"; exit 1 ;;
esac
echo "staged: $1"
