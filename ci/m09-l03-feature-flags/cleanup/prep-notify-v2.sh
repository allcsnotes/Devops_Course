#!/usr/bin/env bash
# prep-notify-v2.sh - run ONCE inside your allcsvideos-ops repo before the flag clean-up (in the video this happened
# off screen, weeks earlier). It finishes the notify v2 work that Module 5 started behind NOTIFY_V2=off:
#   1. CRIT alerts go to the on-call webhook WEBHOOK_URL_CRIT, behind NOTIFY_V2   (one commit)
#   2. NOTIFY_V2 turned on in hc.conf and the test configs                        (one commit)
# Portable (perl instead of GNU sed -i), so it works on macOS and Linux.
set -euo pipefail
[[ -f hc/bin/hc ]] || { echo "run this inside your allcsvideos-ops repo" >&2; exit 1; }
perl -0pi -e 's/send_alert\(\) \{\n  if \[\[ \$NOTIFY_V2 == on \]\]; then   # unfinished: per-severity webhooks\n    echo "hc: NOTIFY_V2 is not ready yet" >&2; return 1\n  fi\n  python3 "\$lib\/report.py" alert "\$WEBHOOK_URL"/send_alert() {\n  local url=\$WEBHOOK_URL\n  if [[ \$NOTIFY_V2 == on ]]; then   # notify v2: CRIT alerts go to the on-call webhook\n    [[ \$2 == CRIT ]] && url=\$WEBHOOK_URL_CRIT\n  fi\n  python3 "\$lib\/report.py" alert "\$url"/' hc/bin/hc
grep -q 'url=$WEBHOOK_URL_CRIT' hc/bin/hc || { echo "hc/bin/hc is not in the expected state" >&2; exit 1; }
perl -pi -e 's/ NOTIFY_V2 CERT_HOSTS\)/ NOTIFY_V2 CERT_HOSTS WEBHOOK_URL_CRIT)/' hc/lib/checks.sh
for f in hc/hc.conf hc/tests/*.conf; do
  perl -pi -e 's|^NOTIFY_V2=off$|WEBHOOK_URL_CRIT=https://alerts.internal/hooks/oncall\nNOTIFY_V2=off|' "$f"
done
git commit -qam 'notify: CRIT alerts to the on-call webhook, behind NOTIFY_V2'
perl -pi -e 's/^NOTIFY_V2=off$/NOTIFY_V2=on/' hc/hc.conf hc/tests/*.conf
git commit -qam 'notify: NOTIFY_V2 on'
bash hc/tests/run.sh | tail -1
echo "now: git push"
