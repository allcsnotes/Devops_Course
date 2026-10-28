#!/bin/sh
# make-repo.sh: builds the starter repository for task 9 (history fixed, so hashes are the same for everyone).
# Commit 2 contains a FAKE AWS key (lab only, never real), removed again in commit 3: it is still in the history.
set -eu
git init -q -b main /repo && cd /repo
git config user.name Priya && git config user.email priya@example.com
export GIT_AUTHOR_DATE="2026-10-01T10:00:00+05:30" GIT_COMMITTER_DATE="2026-10-01T10:00:00+05:30"
printf '# course-search deploy config\n' > README.md
printf 'REGION=ap-south-1\nBUCKET=allcs-videos\n' > deploy.env
git add -A && git commit -qm "deploy: first config"
export GIT_AUTHOR_DATE="2026-10-02T11:00:00+05:30" GIT_COMMITTER_DATE="2026-10-02T11:00:00+05:30"
printf 'AWS_ACCESS_KEY_ID=AKIA2FAKEDEMOKEYZZZZ\nAWS_SECRET_ACCESS_KEY=fakeDEMOsecretKEY0000000000000000000000FAKE\n' >> deploy.env
git add -A && git commit -qm "deploy: keys for the upload job (quick fix)"
export GIT_AUTHOR_DATE="2026-10-03T09:30:00+05:30" GIT_COMMITTER_DATE="2026-10-03T09:30:00+05:30"
printf 'REGION=ap-south-1\nBUCKET=allcs-videos\n' > deploy.env
git add -A && git commit -qm "deploy: remove keys"
git log --oneline
