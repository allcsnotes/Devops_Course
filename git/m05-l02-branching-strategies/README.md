# M05-L02 · Branching Strategies
> Video: Module 5, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- Why branches are cheap to create but expensive to merge late (Priya's three-week branch and its nine conflicts).
- GitFlow (main, develop, feature, release and hotfix branches), built for real, and when it still fits.
- GitHub flow: one main branch, short-lived branches, a pull request, merge, delete.
- Trunk-based development: merge to main at least daily, hide unfinished work behind a feature flag, `git pull --rebase`.
- Release branches cut from trunk, tags, and `git cherry-pick -x` for fixes ("fix on main first").
- Merge commit vs squash vs rebase, branch naming, and four pitfalls: long-lived branches, environment branches, merging main in again and again, branch sprawl.

## Before you start
- Docker Desktop. The lab is one Ubuntu 24.04 container with Git 2.43.0 and three users, **asha**, **priya** and **rahul**, standing in for
  three laptops, plus a bare repository `/srv/git/allcsvideos-ops.git` standing in for GitHub (`origin`).
- [M05-L01](../m05-l01-how-git-really-works/): the lab rebuilds the `allcsvideos-ops` repository exactly as that lesson left it, then adds three
  weeks of team history. **That history is built for the demo, with dates set on purpose** (October 21 to November 13, 2026), but every conflict is real.
- Your commit hashes will differ from the video; use the ones your terminal prints.

## Files in this folder
| File | What it is |
|------|------------|
| `lab/Dockerfile` | Ubuntu 24.04 + Git, users asha / priya / rahul in group `dev`, `/srv/git` for the origin |
| `lab/up.sh` | Builds and starts the `git-team` container, sets each user's Git identity (`@example.com`), builds the repository and its history |
| `lab/l01-repo.sh` | Rebuilds `~asha/allcsvideos-ops` as M05-L01 left it (the webhook token in it is fake, on purpose) |
| `lab/history.sh` | Creates the origin and the clones, then three weeks of team commits; Priya's `feature/notify-rewrite` never integrates |
| `lab/flag-edit.sh` | Priya's editor change to `hc/bin/hc` for the `NOTIFY_V2` flag (step 5) |
| `lab/prep.sh` | Prepares the small demo repositories whose start the video set up off screen (`android`, `merge-demo`, `env-demo`, `search`) |
| `lab/hc-toolkit/` | The health-check toolkit from module 3 (imported into the repository by `history.sh`) |
| `lab/down.sh` | Removes the container and image |

Open a "laptop" with one of:
```bash
docker exec -it -u priya -w /home/priya/allcsvideos-ops git-team bash
docker exec -it -u rahul -w /home/rahul/allcsvideos-ops git-team bash
docker exec -it -u asha  -w /home/asha git-team bash
```

## Follow along

1. Build the lab:
   ```bash
   bash lab/up.sh
   ```

2. **Priya's Friday.** As **priya**:
   ```bash
   git switch feature/notify-rewrite
   git fetch
   git log --oneline origin/main..HEAD | wc -l
   git log --oneline HEAD..origin/main | wc -l
   git log --reverse --format='%ad  %an  %s' --date=short origin/main..HEAD | head -1
   git diff --shortstat origin/main...HEAD
   git diff --shortstat HEAD...origin/main
   git merge origin/main
   ```
   ```
   10
   19
   2026-10-23  Priya  notify: separate webhooks for WARN and CRIT
    9 files changed, 39 insertions(+), 17 deletions(-)
    14 files changed, 60 insertions(+), 13 deletions(-)
   ...
   CONFLICT (content): Merge conflict in hc/hc.conf
   ...
   Automatic merge failed; fix conflicts and then commit the result.
   ```
   Look at the conflicts, then give up for the weekend:
   ```bash
   git diff --name-only --diff-filter=U
   grep -c '^<<<<<<<' $(git diff --name-only --diff-filter=U)
   sed -n '/^<<<<<<</,/^>>>>>>>/p' hc/bin/hc hc/hc.conf
   git merge --abort
   git status --short --branch
   ```
   Nine files, one conflict each. `bin/hc`: `VERSION=2.0.0` vs `VERSION=1.2.0`. `hc.conf`: `CHECK_TIMEOUT` and two webhooks vs
   `HTTP_TIMEOUT=5`, `CERT_DAYS=14` and a moved webhook. A branch is still just a pointer:
   ```bash
   wc -c .git/refs/heads/feature/notify-rewrite
   git log --oneline -1 $(git merge-base HEAD origin/main)
   ```
   `41` bytes, and the branch split from main at `hc.conf: also check redis`, three weeks ago.

3. **GitFlow, built for real** (an Android app shipped as versions). As **asha**, in `~`:
   ```bash
   git init -q gitflow-demo && cd gitflow-demo
   echo 'versionName=1.4.0' > version.properties
   git add . && git commit -qm 'App 1.4.0'
   git tag -a v1.4.0 -m 'Release 1.4.0'
   git switch -c develop
   # feature 1
   git switch -c feature/offline-downloads develop
   echo 'class Downloads' > Downloads.kt
   git add . && git commit -qm 'Downloads: save videos for offline'
   echo 'fun resume() {}' >> Downloads.kt
   git commit -qam 'Downloads: resume interrupted downloads'
   git switch develop
   git merge --no-ff --no-edit feature/offline-downloads
   git branch -d feature/offline-downloads
   # feature 2
   git switch -c feature/dark-mode develop
   echo 'theme=dark' > Theme.kt && git add . && git commit -qm 'Theme: dark mode'
   git switch develop
   git merge --no-ff --no-edit feature/dark-mode
   git branch -d feature/dark-mode
   # release
   git switch -c release/1.5 develop
   sed -i 's/1.4.0/1.5.0/' version.properties
   git commit -qam 'Bump version to 1.5.0'
   echo 'fun onRotate() {}' >> Theme.kt
   git commit -qam 'Fix a crash when the screen rotates'
   git switch main
   git merge --no-ff --no-edit release/1.5
   git tag -a v1.5.0 -m 'Release 1.5.0'
   git switch develop
   git merge --no-ff --no-edit release/1.5
   git branch -d release/1.5
   # hotfix
   git switch -c hotfix/1.5.1 main
   echo 'fun refreshToken() {}' > Login.kt && git add . && git commit -qm 'Fix login when the token expires'
   sed -i 's/1.5.0/1.5.1/' version.properties && git commit -qam 'Bump version to 1.5.1'
   git switch main && git merge --no-ff --no-edit hotfix/1.5.1
   git tag -a v1.5.1 -m 'Release 1.5.1'
   git switch develop && git merge --no-ff --no-edit hotfix/1.5.1
   git branch -d hotfix/1.5.1
   git log --oneline --graph --all
   git branch
   git tag
   ```
   Two features, one release and one hotfix already give six merge commits and crossing lines; `v1.4.0`, `v1.5.0` and `v1.5.1` mark what users got.

4. **GitHub flow** on `allcsvideos-ops`. As **priya**:
   ```bash
   git switch main
   git pull
   git switch -c fix/storefront-https
   sed -i 's|storefront=http://localhost/|storefront=https://localhost/|' hc/hc.conf
   git commit -qam 'hc.conf: check the storefront over HTTPS'
   git push -u origin fix/storefront-https
   ```
   `Fast-forward ... 14 files changed`, then `* [new branch] fix/storefront-https -> fix/storefront-https`.
   As **rahul**, review and merge (what GitHub's merge button does):
   ```bash
   git fetch
   git log --oneline origin/main..origin/fix/storefront-https
   git diff origin/main...origin/fix/storefront-https
   git switch main && git pull -q
   git merge --no-ff --no-edit origin/fix/storefront-https
   git push
   git push origin --delete fix/storefront-https
   ```
   As **priya**:
   ```bash
   git switch main && git pull -q
   git branch -d fix/storefront-https
   git log --oneline --graph -4
   ```
   One commit, one merge: a small bump that lived about an hour.

5. **Trunk-based development.** As **rahul**, a small change straight on main:
   ```bash
   sed -i 's/^LOAD_WARN=1.5/LOAD_WARN=2/' hc/hc.conf
   git commit -qam 'hc.conf: warn at load 2 per CPU'
   git push
   ```
   As **priya**, slice one of the alerts work, behind a flag that is off. `flag-edit.sh` makes her editor change to `hc/bin/hc`:
   ```bash
   bash /opt/flag-edit.sh
   echo 'NOTIFY_V2=off' | tee -a hc/hc.conf hc/tests/*.conf
   sed -i 's/ CERT_DAYS)/ CERT_DAYS NOTIFY_V2)/' hc/lib/checks.sh
   git diff --stat
   git diff hc/bin/hc
   git commit -qam 'notify: NOTIFY_V2 flag, off by default'
   git push
   ```
   `7 files changed, 9 insertions(+), 1 deletion(-)`, then `! [rejected] main -> main (fetch first)`: Rahul pushed first.
   ```bash
   git pull --rebase
   git push
   git log --oneline --graph -4
   ```
   `Successfully rebased and updated refs/heads/main.` and a straight line on top of Rahul's commit.

6. **Release branches from trunk** (the Android app, done trunk-based). From your computer: `bash lab/prep.sh android`. Then as **asha**:
   ```bash
   cd ~/allcsvideos-android
   git log --oneline
   git switch -c release/2.3
   sed -i 's/2.2.0/2.3.0/' version.properties && git commit -qam 'Release 2.3.0'
   git tag -a v2.3.0 -m 'Release 2.3.0'
   git switch main
   echo 'class Search' > Search.kt && git add . && git commit -qm 'Search: filter by language'
   echo 'fun recent() {}' >> Search.kt && git commit -qam 'Search: recent queries'
   echo 'fun noSubtitles() {}' >> Player.kt && git commit -qam 'Player: fix a crash when a video has no subtitles'
   git log --oneline -3
   ```
   The fix landed on main first. Cherry-pick it (use the hash `git log` printed for the fix; the video's was `c6badc4`):
   ```bash
   git switch release/2.3
   git cherry-pick -x <fix-hash>
   sed -i 's/2.3.0/2.3.1/' version.properties && git commit -qam 'Release 2.3.1'
   git tag -a v2.3.1 -m 'Release 2.3.1'
   git log -1 --format=%B HEAD~1
   git log --oneline --graph --all
   ```
   The copied commit's message ends with `(cherry picked from commit ...)`; the release branch holds only what shipped.

7. **Three ways to land a branch.** From your computer: `bash lab/prep.sh merge-demo`. Then as **asha**:
   ```bash
   cd ~/merge-demo
   git log --oneline --graph --all
   git switch -q -c try-merge main
   git merge --no-ff --no-edit feature/player-speed
   git log --oneline --graph -6
   git switch -q -c try-squash main
   git merge --squash feature/player-speed
   git commit -qm 'Player: speed menu'
   git log --oneline --graph -3
   git switch -q -c try-rebase feature/player-speed
   git rebase main
   git log --oneline --graph -5
   ```
   A merge commit with two parents; one squashed commit; or the three commits replayed with new hashes on top of main.

8. **Branch names.** As **priya**:
   ```bash
   git check-ref-format --branch 'feature/notify rewrite'
   git check-ref-format --branch feature/notify-v2
   git branch -r
   ```
   `fatal: 'feature/notify rewrite' is not a valid branch name`; `feature/notify-v2` is fine. Convention: `type/short-description`
   (`feature/`, `fix/`, `release/<version>`, `hotfix/<version>`), lowercase with hyphens.

9. **Pitfalls.**
   Environment branches: from your computer `bash lab/prep.sh env-demo`, then as **asha**:
   ```bash
   cd ~/env-demo
   git log --oneline --graph --all
   git log --oneline --no-merges prod..dev
   git log --oneline --no-merges dev..prod
   ```
   `prod..dev` lists `Player: captions` (expected), but `dev..prod` lists `Hotfix: payment timeout`: missing from dev.

   Merging main in again and again: from your computer `bash lab/prep.sh search`, then as **asha**:
   ```bash
   cd ~/merge-demo
   git log --oneline --graph main~3..feature/search
   git log --oneline --graph main~3..feature/search-rebased
   ```
   Three merges for three commits, vs the same three commits in a straight line.

   Branch sprawl. As **priya**:
   ```bash
   git fetch --prune
   git branch -r --merged origin/main
   git for-each-ref --sort=committerdate --format='%(committerdate:short)  %(refname:short)' refs/remotes/origin
   git push origin --delete fix/timer-jitter
   git branch -r
   ```
   `fix/timer-jitter` is already merged and can go; the spike from `2026-10-22` and the old feature branch each need an owner and a decision.

## Common mistakes
- **Long-lived branches.** If a branch needs more than a couple of days, split the work and hide the unfinished parts behind a flag.
- **Environment branches** (dev / staging / prod promoted by merging). Fixes get lost and every environment runs a different build. Keep one main branch, build one artifact, promote it with different configuration (module 9).
- **Merging main into your feature branch again and again.** It fills the branch with merge commits. Rebase branches nobody else builds on, or better, keep branches short.
- **Branch sprawl.** `git fetch --prune`, `git branch -r --merged`, and delete branches when they merge.
- **Fixing only the release branch.** Fix on main first, then cherry-pick down, or the bug comes back in the next release. No new features on a release branch.

## Clean up
```bash
bash lab/down.sh
```

## Next
[M05-L03 · Merge, Rebase and Fixing Mistakes](../m05-l03-merge-rebase-and-fixing-mistakes/)
