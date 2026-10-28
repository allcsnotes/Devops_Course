#!/usr/bin/env bash
# remove-notify-v2.sh - Priya's editor changes to retire NOTIFY_V2, as a script (run inside allcsvideos-ops; you can
# also make them by hand, see the README). STAGED like the video: it misses the list of known settings in
# hc/lib/checks.sh, so CI goes red until you fix that one word.
set -euo pipefail
[[ -f flags/flags.yaml ]] || { echo "run this inside allcsvideos-ops, after adding flags/" >&2; exit 1; }
perl -0pi -e 's/  if \[\[ \$NOTIFY_V2 == on \]\]; then   # notify v2: CRIT alerts go to the on-call webhook\n    \[\[ \$2 == CRIT \]\] && url=\$WEBHOOK_URL_CRIT\n  fi\n/  [[ \$2 == CRIT ]] && url=\$WEBHOOK_URL_CRIT   # CRIT alerts go to the on-call webhook\n/' hc/bin/hc
perl -ni -e 'print unless /^NOTIFY_V2=on$/' hc/hc.conf hc/tests/*.conf
python3 - <<'PY'
s = open('flags/flags.yaml').read()
i = s.index('  notify-v2:')
open('flags/flags.yaml', 'w').write(s[:i])
PY
echo 'NOTIFY_V2    # notify-v2: v2 is the only path now (priya)' >> flags/removed.txt
