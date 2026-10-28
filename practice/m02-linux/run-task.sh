#!/usr/bin/env bash
# run-task.sh NN : replays the reference answer for task NN (tasks/NN.sh) on your running web-01 container.
# Spoiler, and it CHANGES the server: it applies that answer's fixes. Try the task yourself first.
# Each line of tasks/NN.sh runs as asha in ONE login shell (so cd and variables persist), printed after a "$ " prompt.
#   lines starting with "#" are printed as notes; lines starting with "@" run silently (a short pause, usually).
# Needs the container from the sheet's setup:  docker run ... --name m02lab-web01 ... m02lab-web01
set -euo pipefail
cd "$(dirname "$0")"
n=${1:?usage: ./run-task.sh NN   (for example ./run-task.sh 05)}
C=m02lab-web01
[ -f "tasks/$n.sh" ] || { echo "no such task: tasks/$n.sh" >&2; exit 1; }
docker exec -i "$C" sh -c "cat > /run/lab-task.sh" < "tasks/$n.sh"
docker exec -u asha -w /home/asha -e HOME=/home/asha "$C" bash -lc '
while IFS= read -r l <&3; do
  [ -z "$l" ] && continue
  case "$l" in
    "#"*) echo "$l"; continue;;
    "@"*) eval "${l#@}" </dev/null >/dev/null 2>&1; continue;;
  esac
  printf "\$ %s\n" "$l"
  eval "$l" </dev/null 2>&1
done 3</run/lab-task.sh'
