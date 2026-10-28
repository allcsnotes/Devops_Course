#!/usr/bin/env bash
# backup-uploads.sh: a STAND-IN for a slow backup of /data/uploads. It takes 90 seconds, like a big copy would.
echo "$(date '+%T') backup started, PID $$"
sleep 90
echo "$(date '+%T') backup finished, PID $$"
