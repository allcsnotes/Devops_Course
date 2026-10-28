#!/bin/bash
# The editor change Priya makes to hc/bin/hc for the NOTIFY_V2 flag (applied as priya; shown on screen with git diff).
perl -0pi -e 's/^send_alert\(\) \{\n/send_alert() {\n  if [[ \$NOTIFY_V2 == on ]]; then   # unfinished: per-severity webhooks\n    echo "hc: NOTIFY_V2 is not ready yet" >&2; return 1\n  fi\n/m' ~/allcsvideos-ops/hc/bin/hc
