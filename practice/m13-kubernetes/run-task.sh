#!/usr/bin/env bash
# run-task.sh NN : replays the reference answer for task NN (tasks/NN.sh) in your running tool box (m13lab-tools).
# Spoiler, and it CHANGES the cluster: it applies that answer's fixes. Try the task yourself first.
# Each line runs as asha in ONE bash login shell (so cd, variables and the kubectl context persist),
# printed after a "$ " prompt. Lines starting with "#" are printed as notes; lines starting with "@" run silently.
set -euo pipefail
cd "$(dirname "$0")"
n=${1:?usage: ./run-task.sh NN   (for example ./run-task.sh 04)}
C=m13lab-tools
[ -f "tasks/$n.sh" ] || { echo "no such task: tasks/$n.sh" >&2; exit 1; }
docker exec -i "$C" sh -c "cat > /tmp/lab-task.sh" < "tasks/$n.sh"
docker exec -i "$C" sh -c "cat > /tmp/lab-loop.sh" <<'LOOP'
cd ~
while IFS= read -r l <&3; do
  [ -z "$l" ] && continue
  case "$l" in
    "#"*) echo "$l"; continue;;
    "@"*) eval "${l#@}" </dev/null >/dev/null 2>&1; continue;;
  esac
  printf '$ %s\n' "$l"
  eval "$l" </dev/null 2>&1
done 3</tmp/lab-task.sh
LOOP
docker exec -e COLUMNS=160 "$C" bash -l /tmp/lab-loop.sh
