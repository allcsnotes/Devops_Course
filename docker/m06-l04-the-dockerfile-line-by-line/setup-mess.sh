#!/usr/bin/env bash
# Copies this lesson's files to a lab folder outside the course repo (default ~/m06-l04),
# then recreates the "messy project folder" from the start of the lesson, so the first
# build sweeps the same junk into the image as in the video:
#   copilot/.env                          a FAKE API key (never put a real one here)
#   copilot/.venv/                        a local Python virtual environment
#   copilot/eval/answers-2026-10.jsonl    a ~58 MB evaluation dump
#   copilot/.git/                         a git repository with one commit
#
# Usage (from this lesson folder):   bash setup-mess.sh            -> ~/m06-l04
#                                    bash setup-mess.sh /some/dir  -> /some/dir
# Remove the lab later with:         rm -rf ~/m06-l04
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LAB="${1:-$HOME/m06-l04}"

if [ -e "$LAB" ]; then
  echo "$LAB already exists; remove it first (rm -rf \"$LAB\") or pass another folder" >&2
  exit 1
fi
mkdir -p "$LAB"
cp -R "$HERE/copilot" "$HERE/dockerfiles" "$HERE/combos" "$HERE/argleak" "$LAB/"
cd "$LAB/copilot"

# 1. the FAKE secret
cat > .env <<'EOF'
# FAKE demo values for M06-L04 - not real credentials
LLM_API_KEY=sk-FAKE-demo-key-0000-not-real
EOF

# 2. a local virtual environment (the video's was ~31 MB). Needs python3 on your laptop;
#    without it, the script makes a small placeholder folder instead.
if command -v python3 >/dev/null 2>&1; then
  python3 -m venv .venv
else
  mkdir -p .venv && echo "placeholder venv" > .venv/README
fi

# 3. a big evaluation dump (~58 MB of JSON lines)
mkdir -p eval
awk 'BEGIN { srand(1); for (i = 1; i <= 500000; i++)
  printf "{\"id\": %d, \"q\": \"which course covers docker volumes %d\", \"answer\": \"Try the DevOps course.\", \"latency_ms\": %d}\n",
         i, int(rand() * 60000), 100 + int(rand() * 900) }' > eval/answers-2026-10.jsonl

# 4. a git repository with one commit (author is the lesson persona)
git init -q
git add -A
git -c user.name=Asha -c user.email=asha@example.com commit -q -m "Course Copilot first commit"

du -sh .venv eval .git 2>/dev/null || true
echo "messy project ready in $LAB/copilot"
