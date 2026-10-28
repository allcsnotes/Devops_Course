#!/usr/bin/env bash
# dr-report.sh <disaster time HH:MM:SS.mmm> : the real RPO and RTO of a DR drill
#   RPO: the newest row in the restored database vs the moment of the disaster, and the enrollments the
#        students were told were saved (/acks/acks.csv) that are gone.
#   RTO: the disaster vs the first enrollment that succeeded again.
set -euo pipefail
source ~/bin/backup.env
D=$1
NEWEST=$(psql -Atc "SELECT to_char(max(created_at), 'HH24:MI:SS.MS') FROM enrollments WHERE student <> 'drill@example.com' AND created_at < current_date + time '$D'")
LOST=$(awk -F, -v a="$NEWEST" -v b="$D" '$1 > a && $1 < b' /acks/acks.csv | wc -l)
BACK=$(awk -F, -v b="$D" '$1 > b {print $1; exit}' /acks/acks.csv)
s() { awk -F: '{printf "%.1f", $1*3600 + $2*60 + $3}' <<< "$1"; }
echo "disaster:                    $D"
echo "newest row in the backup:    $NEWEST"
echo "data lost (RPO):             $(awk -v a=$(s $NEWEST) -v b=$(s $D) 'BEGIN{printf "%.0f", b-a}') s, $LOST confirmed enrollments"
echo "first enrollment saved again: $BACK"
echo "enrollments down (RTO):      $(awk -v a=$(s $D) -v b=$(s $BACK) 'BEGIN{printf "%.0f", b-a}') s"
