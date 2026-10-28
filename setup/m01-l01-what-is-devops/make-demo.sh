#!/bin/sh
# Builds a tiny demo Git repo for the allcsvideos web app with a MADE-UP week of history:
# 6 commits, and one annotated Git tag per deploy (deploy-1 ... deploy-6).
# The tag's date is the deploy time, the tag's message is the deploy result.
# Asha works in Mumbai, so all times are +05:30.
#
# usage: sh make-demo.sh [folder]      (default folder: ./allcsvideos-web)
set -e
DIR=${1:-allcsvideos-web}
if [ -e "$DIR" ]; then
  echo "$DIR already exists. Remove it first (rm -rf $DIR) or pass another folder name." >&2
  exit 1
fi
mkdir -p "$DIR" && cd "$DIR"
git init -q -b main
git config user.name "Asha" && git config user.email "asha@example.com"   # only for this demo repo
n=0
c() { # c "<commit time>" "<message>" "<deploy time>" "<deploy result>"
  n=$((n+1)); echo "$2" >> CHANGELOG
  git add CHANGELOG && GIT_AUTHOR_DATE="$1 +0530" GIT_COMMITTER_DATE="$1 +0530" git commit -qm "$2"
  GIT_COMMITTER_DATE="$3 +0530" git tag -a "deploy-$n" -m "$4"
}
c "2026-10-12 10:12" "Add course search box"        "2026-10-12 10:41" "ok: Add course search box"
c "2026-10-13 11:05" "Show lesson length on cards"  "2026-10-13 11:33" "ok: Show lesson length on cards"
c "2026-10-14 15:20" "New checkout page"            "2026-10-14 15:48" "FAILED: checkout errors"
c "2026-10-14 16:02" "Revert New checkout page"     "2026-10-14 16:09" "ok: rollback"
c "2026-10-15 12:00" "Fix checkout page, add test"  "2026-10-15 12:31" "ok: Fix checkout page, add test"
c "2026-10-16 10:04" "Faster video player start"    "2026-10-16 10:30" "ok: Faster video player start"
echo "demo repo ready in $DIR (6 commits, 6 deploy tags)"
