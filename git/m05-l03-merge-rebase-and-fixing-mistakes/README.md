# M05-L03 · Merge, Rebase and Fixing Mistakes
> Video: Module 5, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- Fast-forward vs three-way merge, merge commits with two parents, and `--no-ff`.
- How to read and resolve a conflict: markers, `merge.conflictstyle zdiff3` (shows the base), `--ours` / `--theirs`, `git checkout --merge`.
- Rebase: replaying commits with new hashes, conflicts during a rebase (ours and theirs swap), `rebase -i` (fixup, reword) and `--fixup` + `--autosquash`.
- The golden rule: never rebase history others have; `git pull --rebase` to recover, `--force-with-lease` instead of `--force`.
- Cherry-pick a fix onto a release branch, and undo local work: `restore`, `commit --amend`, `reset --soft / --mixed / --hard`, `ORIG_HEAD`, the reflog, `stash`.
- Find the commit that broke the tests with `git bisect run`, and undo pushed commits (and merges) with `git revert`.

## Before you start
- Docker Desktop. The lab is one Ubuntu 24.04 container (`git-team`) with Git 2.43.0, nano and python3, three users **asha**, **priya** and **rahul**
  standing in for three laptops, and a bare repository `/srv/git/allcsvideos-ops.git` standing in for GitHub.
- [M05-L01](../m05-l01-how-git-really-works/) and [M05-L02](../m05-l02-branching-strategies/). The lab rebuilds the repository as M05-L02 left it
  (**team history built for the demo, with dates set on purpose**), tags `v1.2.0`, creates `release/1.2`, and gives Priya a local, never-pushed
  branch `feature/cert-check` with four messy commits. If the M05-L02 lab is still running, remove it first (`bash ../m05-l02-branching-strategies/lab/down.sh`).
- The teammates' commits that happen off screen in the video are made with `lab/stage.sh`. Every conflict, the bug and the mistakes are staged on purpose.
- Your hashes differ from the video; always use the ones your terminal prints.

## Files in this folder
| File | What it is |
|------|------------|
| `lab/Dockerfile` | Ubuntu 24.04 + Git, nano, python3; users asha / priya / rahul in group `dev` |
| `lab/up.sh` | Builds and starts `git-team`, sets each user's identity (`@example.com`) and `core.editor nano`, builds the repository |
| `lab/l01-repo.sh` | Rebuilds `allcsvideos-ops` as M05-L01 left it (contains a fake token, on purpose) |
| `lab/history.sh` | M05-L02's three weeks of team history (origin + three clones) |
| `lab/flag-edit.sh` | Priya's `NOTIFY_V2` editor change from M05-L02 (replayed by `setup.sh`) |
| `lab/setup.sh` | Replays M05-L02's steps, adds `v1.2.0`, `release/1.2` and Priya's `feature/cert-check` |
| `lab/stage.sh` | The teammates' off-screen commits: `rahul-logrotate`, `wednesday`, `shared-branch`, `spike`, `two-commits`, `demo-conflict` |
| `lab/hc-toolkit/` | The health-check toolkit (its `tests/run.sh` is what `git bisect` runs) |
| `lab/down.sh` | Removes the container and image |

Open a laptop with:
```bash
docker exec -it -u asha  -w /home/asha/allcsvideos-ops  git-team bash
docker exec -it -u priya -w /home/priya/allcsvideos-ops git-team bash
docker exec -it -u rahul -w /home/rahul/allcsvideos-ops git-team bash
```

## Follow along

1. Build the lab: `bash lab/up.sh`.

2. **Fast-forward.** As **asha**:
   ```bash
   git switch -q main && git pull -q
   git switch -c docs/readme-tests
   echo 'Tests: bash hc/tests/run.sh' >> README.md
   git commit -qam 'README: how to run the tests'
   git switch main
   git merge docs/readme-tests
   git push -q
   git log --oneline --graph -3
   ```
   `Updating ... Fast-forward`: main just slides forward, no new commit.

3. **Three-way merge.** As **asha**:
   ```bash
   git switch -c hc/check-var-log
   sed -i 's|^MOUNTS=/ /data$|MOUNTS=/ /data /var/log|' hc/hc.conf
   git commit -qam 'hc.conf: also check /var/log'
   git switch main
   ```
   Meanwhile Rahul pushes to main (from your computer): `bash lab/stage.sh rahul-logrotate`. Then as **asha**:
   ```bash
   git pull
   git merge-base main hc/check-var-log
   git log --oneline --graph --all -4 main hc/check-var-log
   git merge --no-edit hc/check-var-log
   git log --oneline --graph -5
   git cat-file -p HEAD
   ```
   `Merge made by the 'ort' strategy.` and the merge commit has **two** `parent` lines. Then `--no-ff`:
   ```bash
   git switch -c docs/exit-codes
   echo 'Exit codes: 0 OK, 1 WARN, 2 CRIT, 3 UNKNOWN' >> README.md
   git commit -qam 'README: list the exit codes'
   git switch main
   git merge --no-ff --no-edit docs/exit-codes
   git log --oneline --graph -4
   git push -q
   git branch -d docs/readme-tests hc/check-var-log docs/exit-codes
   ```

4. **A real conflict.** From your computer: `bash lab/stage.sh wednesday` (Asha's branch raises `DISK_CRIT` to 95; Priya raises `DISK_WARN` to 85 on main; plus a few more team commits). As **asha**:
   ```bash
   git switch -q tune/disk-thresholds
   git log --oneline -1
   git fetch -q
   git merge origin/main
   git status
   sed -n '/^<<<<<<</,/^>>>>>>>/p' hc/hc.conf
   git diff
   ```
   `CONFLICT (content): Merge conflict in hc/hc.conf`, `both modified: hc/hc.conf`, and the two sides (`75/95` vs `85/90`). Now see the base:
   ```bash
   git merge --abort
   git status --short --branch
   git config --global merge.conflictstyle zdiff3
   git merge origin/main
   sed -n '/^<<<<<<</,/^>>>>>>>/p' hc/hc.conf
   ```
   ```
   <<<<<<< HEAD
   DISK_WARN=75
   DISK_CRIT=95
   ||||||| 8dba332
   DISK_WARN=75
   DISK_CRIT=90
   =======
   DISK_WARN=85
   DISK_CRIT=90
   >>>>>>> origin/main
   ```
   Each side changed a different line: keep both. First see what taking one side would do, then put the conflict back:
   ```bash
   git checkout --theirs hc/hc.conf
   grep '^DISK_' hc/hc.conf
   git checkout --merge hc/hc.conf
   grep -c '^<<<<<<<' hc/hc.conf
   head -12 hc/hc.conf
   ```
   Resolve it in your editor (`nano hc/hc.conf`): keep `DISK_WARN=85` and `DISK_CRIT=95`, delete every marker line and the old lines.
   (Same edit in one command: `perl -0pi -e 's/^<<<<<<< ours\n(.*\n)*?>>>>>>> theirs\n/DISK_WARN=85\nDISK_CRIT=95\n/m' hc/hc.conf`.) Then:
   ```bash
   head -6 hc/hc.conf
   git diff
   grep -cE '^(<<<<<<<|=======|>>>>>>>)' hc/hc.conf
   git add hc/hc.conf
   git status
   git commit --no-edit
   git log --oneline --graph -4
   git switch main
   git pull -q
   git merge tune/disk-thresholds
   git push -q
   git branch -d tune/disk-thresholds
   ```
   `0` marker lines, `All conflicts fixed but you are still merging`, then a merge commit, and landing the branch is a fast-forward.

5. **Rebase.** As **priya**:
   ```bash
   git switch -q feature/cert-check
   git config --global merge.conflictstyle zdiff3
   git fetch -q
   git log --oneline origin/main..HEAD
   git log --oneline HEAD..origin/main | wc -l
   git rebase origin/main
   git status
   sed -n '/^<<<<<<</,/^>>>>>>>/p' hc/hc.conf
   ```
   Four commits (`checks: add check_cert`, `wip`, `fix typo`, `docs`), 13 new on main, then `could not apply ... checks: add check_cert`.
   The markers show `HEAD` = main (`CERT_DAYS=30`) and her commit (`21`): **in a rebase, ours and theirs swap**. Take main's 30 and continue
   (nano opens with the original message: just save with Ctrl-X):
   ```bash
   git checkout --ours hc/hc.conf
   grep '^CERT_DAYS' hc/hc.conf
   git add hc/hc.conf
   git rebase --continue
   git log --oneline origin/main..HEAD
   git log --oneline -1 <old-hash-of-checks-add-check_cert>
   ```
   Four new hashes; the old first commit still exists, on no branch.

6. **Clean up before review.** As **priya**:
   ```bash
   git rebase -i origin/main
   ```
   In nano change `pick` to `fixup` for `wip` and `fix typo`, and to `reword` for `docs`; save (Ctrl-X, y, Enter). At the reword, replace the
   message with `README: document CERT_DAYS` and save. Then:
   ```bash
   git log --oneline origin/main..HEAD
   git show --stat --format='%h %s' HEAD~1
   ```
   Two commits. Review asks for a timeout on the openssl call. Make that editor change, fold it in, and push:
   ```bash
   sed -i 's/^  end=$(openssl s_client/  end=$(timeout 5 openssl s_client/' hc/lib/checks.sh
   git diff --stat
   git commit -a --fixup=HEAD~1
   git log --oneline origin/main..HEAD
   git rebase -i --autosquash origin/main
   git log --oneline origin/main..HEAD
   git push -u origin feature/cert-check
   ```
   `--autosquash` already moved `fixup! checks: add check_cert` under its target; just save (Ctrl-X). Everything rewritten so far existed only on her laptop.

7. **The golden rule.** From your computer: `bash lab/stage.sh shared-branch` (a shared branch `feature/notify-v2`, pushed by Priya and Asha;
   one more commit on Priya's laptop, not pushed; and Rahul's timer fix on main). As **asha**:
   ```bash
   git switch -q feature/notify-v2 && git pull -q
   git log --oneline -2
   git fetch -q
   git rebase origin/main
   git push
   git push --force
   ```
   `! [rejected] ... (non-fast-forward)`, then `+ ... (forced update)`. As **priya**:
   ```bash
   git switch -q feature/notify-v2
   git pull
   git status --short --branch
   git log --oneline --graph HEAD origin/feature/notify-v2 ^origin/main
   git pull --rebase
   git log --oneline --graph -4
   git push -q
   ```
   `fatal: Need to specify how to reconcile divergent branches`, `[ahead 3, behind 3]`, the same two commits twice; `git pull --rebase` replays
   only her own commit. As **asha**, try `--force-with-lease`:
   ```bash
   git commit -q --amend -m 'README: document the NOTIFY_V2 flag'
   git push --force-with-lease
   git fetch -q
   git log --oneline -1 origin/feature/notify-v2
   git reset -q --hard origin/feature/notify-v2 && git switch -q main
   ```
   `! [rejected] ... (stale info)`: a plain `--force` would have silently deleted Priya's new commit.

8. **Landing a branch, three ways, then cherry-pick.** As **rahul**:
   ```bash
   git switch -q main && git pull -q
   git fetch -q
   git switch -q -c try-merge origin/main
   git merge --no-ff --no-edit origin/feature/cert-check
   git log --oneline --graph -4
   git switch -q -c try-squash origin/main
   git merge --squash origin/feature/cert-check
   git commit -qm 'Add the certificate check'
   git log --oneline --graph -2
   git switch -q -c try-rebase origin/feature/cert-check
   git rebase origin/main
   git log --oneline --graph -3
   git switch -q main && git branch -q -D try-merge try-squash try-rebase
   git merge --no-ff --no-edit origin/feature/cert-check
   git push -q
   git push -q origin --delete feature/cert-check
   git log --oneline --graph -4
   ```
   Now ship Rahul's timer fix to the servers on `release/1.2`. As **asha** (use the hash of `timer: catch up missed runs...`):
   ```bash
   git switch -q main && git pull -q
   git log --oneline -3
   git switch release/1.2
   git cherry-pick -x <timer-fix-hash>
   git log -1 --format=%B
   git log --oneline -3
   git push -q origin release/1.2
   ```
   A new commit (same change, same author and date, new parent and hash) ending in `(cherry picked from commit ...)`.

9. **Undo local work.** From your computer: `bash lab/stage.sh spike` (Asha's `spike/json-alerts`, used in step 11). As **asha**:
   ```bash
   git switch -q main && git pull -q
   echo 'MEM_CRIT=1' >> hc/hc.conf
   git status --short
   git restore hc/hc.conf
   git status --short
   sed -i 's/^MEM_CRIT=10$/MEM_CRIT=5/' hc/hc.conf
   git commit -am 'hc.conf: lower MEM_CRT'
   git commit --amend -m 'hc.conf: critical at 5% available memory'
   sed -i 's|20% / 10% or less available|15% / 5% or less available|' hc/README.md
   git add hc/README.md
   git commit --amend --no-edit
   git log --oneline -2
   ```
   Three hashes for one commit: amend replaces, it never edits.

10. **reset --soft / --mixed / --hard.** As **asha**:
    ```bash
    git reset --soft HEAD~1
    git status --short
    git log --oneline -1
    git commit -qm 'hc.conf: critical at 5% available memory'
    git reset HEAD~1
    git status --short
    git commit -qam 'hc.conf: critical at 5% available memory'
    git reset --hard HEAD~1
    git status --short
    grep '^MEM_CRIT' hc/hc.conf
    ```
    `M ` (staged) after `--soft`, ` M` (unstaged) after `--mixed`, nothing and `MEM_CRIT=10` after `--hard`. Get it back:
    ```bash
    git reflog -4
    git rev-parse --short ORIG_HEAD
    git reset --hard ORIG_HEAD
    grep '^MEM_CRIT' hc/hc.conf
    ```

11. **The Friday scare, and a deleted branch.** From your computer: `bash lab/stage.sh two-commits`. As **asha**:
    ```bash
    git log --oneline -4
    git reset --hard HEAD~3
    git log --oneline -3
    git reflog -3
    git reset --hard HEAD@{1}
    git reset --hard HEAD~1
    git log --oneline -3
    git branch -D spike/json-alerts
    git log --oneline -1 spike/json-alerts
    git reflog | grep -m2 'spike'
    git branch spike/json-alerts <hash-from-the-delete-message>
    git log --oneline -2 spike/json-alerts
    ```
    All three commits come back, then the reset she meant (`HEAD~1`) drops only the experiment. The deleted branch comes back from the hash
    Git printed (`Deleted branch spike/json-alerts (was ...)`).

12. **stash.** As **asha**:
    ```bash
    sed -i 's|^MOUNTS=/ /data /var/log$|MOUNTS=/ /data /var/log /srv|' hc/hc.conf
    git status --short
    git stash
    git stash list
    git status --short
    git push -q
    git stash pop
    ```
    Keep that popped `/srv` edit uncommitted: step 14 uses it.

13. **bisect and revert.** As **rahul**:
    ```bash
    git switch -q main && git pull -q
    bash hc/tests/run.sh
    git bisect start
    git bisect bad
    git bisect good v1.2.0
    git bisect run sh -c 'bash hc/tests/run.sh > /dev/null'
    ```
    `12 passed, 1 failed` (`rate 80 is WARN: expected 'WARN', got 'OK'`), then `... is the first bad commit` for `checks: simplify rate()`.
    ```bash
    git show --format='%h %an %s' <first-bad-hash>
    git bisect reset
    git revert --no-edit <first-bad-hash>
    bash hc/tests/run.sh | tail -2
    git log -1 --format=%B
    git push -q
    ```
    `>=` became `>`; after the revert: `13 passed, 0 failed` and `This reverts commit ...`. Reverting a merge needs `-m` (use the hash of the
    `Merge remote-tracking branch 'origin/feature/cert-check'` commit):
    ```bash
    git switch -q -c try-revert-merge
    git revert --no-edit <cert-check-merge-hash>
    git revert -m 1 --no-edit <cert-check-merge-hash>
    git show --stat --format='%h %s' HEAD
    git switch -q main && git branch -q -D try-revert-merge
    ```
    `error: commit ... is a merge but no -m option was given.`, then the revert removes the README lines and `check_cert`.

14. **Pitfalls.** `reset --hard` with uncommitted work. As **asha** (the `/srv` edit from step 12 is still uncommitted):
    ```bash
    git status --short
    git diff
    git reset --hard
    git status --short
    git reflog -2
    git stash list
    git pull -q
    ```
    The edit is gone, and neither the reflog nor the stash has it. Block force-pushes on the server. As **rahul**, then as **asha**:
    ```bash
    git -C /srv/git/allcsvideos-ops.git config receive.denyNonFastForwards true
    ```
    ```bash
    git push --force origin HEAD~1:main
    ```
    `! [remote rejected] HEAD~1 -> main (non-fast-forward)`. Conflict markers: from your computer `bash lab/stage.sh demo-conflict`, then as **asha**:
    ```bash
    git merge demo-b
    git add hc/hc.conf
    git diff --cached --check
    hc/bin/hc -n -c hc/hc.conf
    printf '#!/bin/sh\nexec git diff --cached --check\n' > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    git commit --no-edit
    git merge --abort
    git switch -q main && git branch -q -D demo-a demo-b && rm .git/hooks/pre-commit
    ```
    `leftover conflict marker` four times, `hc: unknown setting <<<<<<< HEAD`, and the pre-commit hook stops the commit.

**Which undo?** Not committed: `restore` or `stash`. Committed, not pushed: `amend`, `reset`, `rebase -i`. Pushed: `revert`. Lost something: the reflog
(entries expire after 90 days, or 30 for unreachable commits; it's local to your clone).

## Common mistakes
- **`reset --hard` with uncommitted work.** The reflog only records commits. Commit or stash first.
- **Force-pushing shared branches.** Never rebase history others have. If you must force-push your own branch, use `--force-with-lease`. Protect main on the server (GitHub: branch protection, next lesson).
- **Resolving a conflict by deleting the other side unread.** Read the base with `zdiff3` and run the tests after every resolution.
- **Committing conflict markers.** `git diff --cached --check` catches them; put it in a pre-commit hook (CI does it for everyone in module 8).
- **Forgetting that ours/theirs swap during a rebase.**
- **Reverting a merge, then merging the branch again.** The changes don't come back; you'd have to revert the revert.

## Clean up
```bash
bash lab/down.sh
```

## Next
[M05-L04 · The Pull-Request Workflow](../m05-l04-the-pull-request-workflow/)
