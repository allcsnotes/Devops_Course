#!/usr/bin/env bash
# run-task.sh NN USER : replays the reference answer for scenario NN (tasks/NN.sh) as USER (asha or priya)
# on your running m05lab-lab container. Spoiler, and it CHANGES the repositories: try the scenario yourself first.
# Each line runs in ONE login shell (so cd and variables persist), printed after a "$ " prompt.
#   lines starting with "#" are printed as notes; lines starting with "@" run silently.
# The shell runs under `script`, so Git behaves as in a real terminal; colours and the pager are switched off.
set -euo pipefail
cd "$(dirname "$0")"
n=${1:?usage: ./run-task.sh NN USER   (for example ./run-task.sh 03 asha)}
u=${2:?usage: ./run-task.sh NN USER   (USER is asha or priya)}
C=m05lab-lab
[ -f "tasks/$n.sh" ] || { echo "no such task: tasks/$n.sh" >&2; exit 1; }
docker exec -i "$C" sh -c "cat > /tmp/lab-task.sh && chmod 644 /tmp/lab-task.sh" < "tasks/$n.sh"
docker exec -i "$C" sh -c "cat > /tmp/lab-loop.sh && chmod 644 /tmp/lab-loop.sh" <<'LOOP'
export GIT_PAGER=cat PAGER=cat GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=color.ui GIT_CONFIG_VALUE_0=never
stty cols 200 2>/dev/null
cd ~
while IFS= read -r l <&3; do
  [ -z "$l" ] && continue
  case "$l" in
    "#"*) echo "$l"; continue;;
    "@"*) eval "${l#@}" </dev/null >/dev/null 2>&1; continue;;
  esac
  printf "\$ %s\n" "$l"
  eval "$l" </dev/null 2>&1
done 3</tmp/lab-task.sh
LOOP
# strip the carriage returns and escape codes that `script` adds
docker exec -u "$u" -w "/home/$u" -e HOME="/home/$u" "$C" script -qec "bash -l /tmp/lab-loop.sh" /dev/null \
  | perl -pe 's/\r\n/\n/g; s/^.*\r(?=.)//mg; s/\x1b\[[0-9;?]*[A-Za-z]//g; s/\x1b\][^\a]*\a//g'
