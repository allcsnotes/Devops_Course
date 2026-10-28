# M05-L04 · The Pull-Request Workflow
> Video: Module 5, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- Why a pull request is the safe path to main, and the life of one: branch, push, open, review, CI, merge, delete.
- Branch protection (no direct pushes, required approvals, required status checks, up-to-date branches, rules for admins too) and CODEOWNERS.
- How to write a small pull request with a clear description, and how to review with labelled comments (Conventional Comments).
- The server's merge styles (merge, rebase, squash, fast-forward) and a linear main.
- Semantic versioning (MAJOR.MINOR.PATCH), Conventional Commits, SSH-signed annotated tags, `git describe` and release notes.
- Monorepo vs polyrepo, and five pitfalls: giant PRs, rubber stamps, gatekeeping, admin bypass, tagging the wrong commit.

## Before you start
- Docker Desktop. The lab runs **Gitea 28.1.0** (`gitea/gitea:28.1.0`), a real self-hosted Git server, next to the team machine from lessons 2 and 3
  (Ubuntu 24.04, Git 2.43.0, and `tea` 0.16.0, Gitea's command-line client). GitHub and GitLab work the same way; only the names differ:

  | Gitea | GitHub | GitLab |
  |-------|--------|--------|
  | pull request | pull request | merge request |
  | branch protection | branch protection rules / rulesets | protected branches |
  | CODEOWNERS (`.gitea/`, root or `docs/`; Go regular expressions) | CODEOWNERS (`.github/`, root or `docs/`; gitignore-style, last match wins) | CODEOWNERS |
  | status checks | status checks | pipelines |
  | `tea pulls create` | `gh pr create` | |

- [M05-L01](../m05-l01-how-git-really-works/) to [M05-L03](../m05-l03-merge-rebase-and-fixing-mistakes/). The lab rebuilds the team repository as those lessons
  left it (**history built for the demo, with dates set on purpose**). If the M05-L03 lab is still running, remove it first (`bash ../m05-l03-merge-rebase-and-fixing-mistakes/lab/down.sh`).
- Port 3000 on your computer must be free (the Gitea web UI is published on `http://localhost:3000`, on 127.0.0.1 only).
- Hashes and dates will differ from the video; pull-request numbers match if you follow the steps in order (#1, issue #2, #3, #4, #5).

## Files in this folder
| File | What it is |
|------|------------|
| `files/CODEOWNERS` | Who reviews what: `hc/hc.conf` Rahul; `hc/systemd/` and `hc/lib/` Asha; the CODEOWNERS file itself Asha |
| `files/protect-main.json` | The branch protection rule for main, as Gitea's REST API takes it |
| `files/pr-description.md` | Priya's pull-request description: What, Why (`Closes #2`), How to test |
| `lab/accounts.env.example` | Copy to `lab/accounts.env` and set **your own** throwaway lab passwords |
| `lab/up.sh` | Starts Gitea and the `git-team` machine, rebuilds the repository and history, creates the Gitea accounts asha and ci-bot |
| `lab/forge.sh` | Creates access tokens (never printed), `tea` logins, the `allcsvideos` organisation, team `devs`, and the empty repository |
| `lab/ci.sh` + `lab/lab-ci.sh` + `lab/check-config.sh` | The lab's stand-in for CI: runs the config check and the tests on a pull request and posts the status `ci/hc-tests` (module 8 builds real CI) |
| `lab/stage.sh` | What the video does in the web UI or off screen: `protect`, `review`, `update`, `version-pr`, `docs-pr` |
| `lab/Dockerfile`, `lab/l01-repo.sh`, `lab/history.sh`, `lab/setup.sh`, `lab/flag-edit.sh`, `lab/hc-toolkit/` | The team machine and the repository history from lessons 1 to 3 |
| `lab/down.sh` | Removes everything, including all lab accounts and tokens |

Open a laptop with:
```bash
docker exec -it -u asha  -w /home/asha/allcsvideos-ops  git-team bash
docker exec -it -u priya -w /home/priya/allcsvideos-ops git-team bash
docker exec -it -u rahul -w /home/rahul/allcsvideos-ops git-team bash
```

## Follow along

1. Set your lab passwords and start everything:
   ```bash
   cp lab/accounts.env.example lab/accounts.env      # then edit it: your own throwaway passwords
   bash lab/up.sh
   ```

2. **The hook: a push straight to main** (staged on purpose; origin is still the bare repository from lessons 2 and 3).
   As **asha**, **priya** and **rahul** first: `git switch -q main && git pull -q`. Then as **priya**:
   ```bash
   sed -i 's/^HTTP_TIMEOUT=/HTTP_TIMEOUT_SECONDS=/' hc/hc.conf
   git commit -qam 'hc.conf: clearer name for the HTTP timeout'
   git push
   ```
   As **asha**:
   ```bash
   git pull -q
   git log --oneline -2
   hc/bin/hc -n -c hc/hc.conf; echo "exit $?"
   git revert --no-edit HEAD
   git push -q
   hc/bin/hc --version
   ```
   `hc: unknown setting HTTP_TIMEOUT_SECONDS in hc/hc.conf`, `exit 3`: not one health check would run. The revert fixes it (`hc 1.2.0`).

3. **The team on Gitea.** Create Priya's and Rahul's accounts with Gitea's admin tool (from your computer, in this folder):
   ```bash
   . lab/accounts.env
   docker exec -u git gitea gitea admin user create --username priya --email priya@example.com --password "$LAB_PASS_PRIYA" --must-change-password=false
   docker exec -u git gitea gitea admin user create --username rahul --email rahul@example.com --password "$LAB_PASS_RAHUL" --must-change-password=false
   docker exec -u git gitea gitea admin user list
   bash lab/forge.sh
   ```
   ```
   New user 'priya' has been successfully created!
   New user 'rahul' has been successfully created!
   ID   Username Email              IsActive IsAdmin 2FA
   1    asha     asha@example.com   true     true    false
   2    ci-bot   ci-bot@example.com true     false   false
   3    priya    priya@example.com  true     false   false
   4    rahul    rahul@example.com  true     false   false
   allcsvideos/allcsvideos-ops
   ```
   Move origin to Gitea. As **asha**:
   ```bash
   git remote set-url origin http://gitea:3000/allcsvideos/allcsvideos-ops.git
   git push -u origin main release/1.2
   git push -q origin --tags
   git remote -v
   ```
   As **priya** and **rahul**:
   ```bash
   git remote set-url origin http://gitea:3000/allcsvideos/allcsvideos-ops.git && git fetch -q --prune origin && git pull -q
   ```
   Browse it at `http://localhost:3000/allcsvideos/allcsvideos-ops` (sign in with the lab passwords). Links Gitea prints use `http://gitea:3000`,
   the address inside the lab; in your browser use `localhost:3000` instead.

4. **CODEOWNERS.** From your computer: `docker cp files/CODEOWNERS git-team:/tmp/CODEOWNERS`. As **asha** (the last direct push to main):
   ```bash
   mkdir -p .gitea && cp /tmp/CODEOWNERS .gitea/CODEOWNERS
   cat .gitea/CODEOWNERS
   git add .gitea/CODEOWNERS
   git commit -qm 'Add CODEOWNERS: who reviews what'
   git push -q
   ```

5. **Branch protection for main.** In the web UI as asha: repository **Settings > Branches > Add / edit rule `main`**, and set:
   push disabled, force push disabled, required approvals `1`, dismiss stale approvals, enable status check with pattern `ci/hc-tests`,
   block merge on rejected reviews, require approval from code owners, block merge if the pull request is outdated, and
   administrators must follow branch protection rules. Or apply the same rule from your computer:
   ```bash
   bash lab/stage.sh protect
   ```
   (On GitHub: require a pull request before merging, required approvals, require review from code owners, require status checks,
   require branches to be up to date; and turn on "do not allow bypassing the above settings", because admins can bypass by default.)

6. **A direct push is rejected; open a pull request instead.** As **rahul**:
   ```bash
   sed -i 's/^RandomizedDelaySec=20s/RandomizedDelaySec=30s/' hc/systemd/hc.timer
   git commit -qam 'hc.timer: spread the runs over 30 seconds'
   git push
   ```
   ```
   remote: error: Not allowed to push to protected branch main
    ! [remote rejected] main -> main (pre-receive hook declined)
   ```
   ```bash
   git switch -c fix/timer-spread
   git push -u origin fix/timer-spread
   git branch -f main origin/main
   tea pulls create --title 'hc.timer: spread the runs over 30 seconds' --description 'Every server starts hc inside the same 20 s window. A 30 s spread evens out the load on the health endpoints. Only RandomizedDelaySec changes.'
   ```
   Pull request **#1**. Run the lab CI for it (from your computer) and look at the PR page: CODEOWNERS requested a review from asha (it touches
   `hc/systemd`), `ci/hc-tests` is green and Required, but merging is blocked (0 of 1 approvals, no code-owner approval):
   ```bash
   bash lab/ci.sh 1
   ```
   ```
   config ok: hc/hc.conf
   ...
   13 passed, 0 failed
   result: success
   ```

7. **Priya's pull request, done properly.** As **rahul**, an issue:
   ```bash
   tea issues create --title 'Certificate check: which hosts?' --description 'check_cert needs to know which public hosts to check. Add a setting for the list.'
   ```
   Issue **#2** (issues and pull requests share one counter). From your computer: `docker cp files/pr-description.md git-team:/home/priya/pr.md && docker exec git-team chown priya:priya /home/priya/pr.md`. As **priya**:
   ```bash
   git switch -q main && git pull -q
   git switch -c feature/cert-hosts
   sed -i '/^CERT_DAYS=/a CERT_HOSTS=allcsvideos.com api.allcsvideos.com' hc/hc.conf
   git diff
   git commit -qam 'hc.conf: add CERT_HOSTS, the hosts for the certificate check'
   git push -q -u origin feature/cert-hosts
   cat ~/pr.md
   tea pulls create --title 'Add CERT_HOSTS for the certificate check' --description-file ~/pr.md
   ```
   Pull request **#3**. CI (from your computer):
   ```bash
   bash lab/ci.sh 3
   ```
   `hc: unknown setting CERT_HOSTS in hc/hc.conf` ... `13 passed, 0 failed` ... `result: failure`: the config check fails, so the status is red.
   The same kind of mistake as the hook, caught on a branch.

8. **Review.** Rahul requests changes with labelled comments under the `CERT_HOSTS` line: `praise:` for what's good, `issue (blocking):` for
   what must change, `question (non-blocking):` for curiosity. Do it in the web UI as rahul (Files changed > comment on the line > Review > Request changes), or:
   ```bash
   bash lab/stage.sh review 3
   ```
   Priya fixes it. As **priya**:
   ```bash
   sed -i 's/ NOTIFY_V2)/ NOTIFY_V2 CERT_HOSTS)/' hc/lib/checks.sh
   for f in hc/tests/*.conf; do echo 'CERT_HOSTS=' >> $f; done
   bash hc/tests/run.sh | tail -1
   git commit -qam 'checks: CERT_HOSTS is a known setting'
   git push -q
   ```
   Then `bash lab/ci.sh 3` turns it green. Her new commit touches `hc/lib`, so Gitea now also requests a review from asha.

9. **Approvals, an admin who can't bypass, and the merge.** As **asha**, approve #1; as **rahul**, merge it with a rebase and clean up, then approve #3:
   ```bash
   tea pulls approve 1 'Looks good: one value, and runs stay inside the 2 minute interval.'          # asha
   ```
   ```bash
   tea pulls merge --style rebase 1                                                                 # rahul
   tea pulls clean 1
   tea pulls approve 3 'CI is green and CERT_HOSTS is in KEYS. Thanks!'
   ```
   Main just moved, so #3 is outdated and still needs a code-owner approval. As **asha** (the admin), try anyway:
   ```bash
   tea pulls merge --style squash 3
   ```
   `Error: failed to merge PR #3: the server refused the merge ...`. Admins follow the rules too. Priya presses **Update branch by merge**
   on the PR page (or `bash lab/stage.sh update 3`), CI runs again (`bash lab/ci.sh 3`), and asha approves for `hc/lib`:
   ```bash
   tea pulls approve 3 'Fine for hc/lib: one more known setting.'                                   # asha
   ```
   Every rule is green. As **priya**:
   ```bash
   git pull -q
   tea pulls merge --style squash 3
   tea pulls clean 3
   git pull -q
   git log --oneline -3
   ```
   `Add CERT_HOSTS for the certificate check (#3)` on main, and issue #2 closed itself because the description said `Closes #2`. As **asha**:
   ```bash
   git pull -q
   git log --oneline --graph -6
   ```
   A squash commit, a rebased commit, and no merge commits at all. (GitHub's "require linear history"; in Gitea, allow only squash, rebase or fast-forward merges in the repository settings.)

10. **Release 1.3.0** (a new optional setting = MINOR). The version bump goes through its own pull request #4 (from your computer):
    ```bash
    bash lab/stage.sh version-pr
    ```
    As **asha**, an SSH key for signing, then a signed annotated tag:
    ```bash
    ssh-keygen -q -t ed25519 -N '' -C asha@example.com -f ~/.ssh/tagkey
    git config --global gpg.format ssh
    git config --global user.signingkey ~/.ssh/tagkey.pub
    echo "asha@example.com $(cat ~/.ssh/tagkey.pub)" > ~/.ssh/allowed_signers
    git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
    git log --oneline -1
    git tag -s v1.3.0 -m 'hc 1.3.0'
    git tag -v v1.3.0
    git push origin v1.3.0
    git describe
    hc/bin/hc --version
    git tag -l --sort=-v:refname
    git log --oneline --no-merges v1.2.0..v1.3.0
    git log --format='- %s' --no-merges v1.2.0..v1.3.0 > ~/notes.md
    tea releases create --tag v1.3.0 --title 'hc 1.3.0' --note-file ~/notes.md
    ```
    `Good "git" signature for asha@example.com with ED25519 key ...`, `v1.3.0`, `hc 1.3.0`, and a release page under Releases.
    (The `-N ''` key has no passphrase: fine for this lab only.)

11. **Pitfall: tagging the wrong commit** (staged on purpose). First Priya's docs pull request #5 lands (from your computer):
    ```bash
    bash lab/stage.sh docs-pr
    ```
    As **rahul**, whose local main is behind:
    ```bash
    git fetch -q
    git status -sb | head -1
    git tag -a v1.3.1 -m 'hc 1.3.1: CERT_HOSTS documented'
    git log --oneline -1 v1.3.1
    git merge-base --is-ancestor v1.3.0 v1.3.1; echo $?
    git tag -d v1.3.1
    git pull -q
    git log --oneline -1
    git describe
    ```
    `[behind 4]`, the tag lands on `Add CODEOWNERS`, and `1`: v1.3.1 doesn't even contain v1.3.0. It wasn't pushed, so delete it and pull;
    `git describe` now says `v1.3.0-1-g...`. Pull, check, then tag. Never move a tag that's already pushed: release the next version instead.

### Semantic versioning in one table
| Change to hc (the config file is its API) | Version |
|---|---|
| a fixed false alarm (backward-compatible fix) | PATCH: 1.2.1 |
| a new optional setting like `CERT_HOSTS` | MINOR: 1.3.0 |
| renaming `HTTP_TIMEOUT` (breaks every existing `hc.conf`) | MAJOR: 2.0.0 (pre-releases first: `2.0.0-rc.1`) |

Conventional Commits: `fix:` correlates with PATCH, `feat:` with MINOR, `!` or a `BREAKING CHANGE:` footer with MAJOR.

### Monorepo or polyrepo?
| | Monorepo | Polyrepo |
|---|---|---|
| Atomic changes | one PR changes API and storefront together | several PRs, coordinated and released in order |
| Ownership | CODEOWNERS per folder | permissions per repository |
| CI cost | must filter by path, or every change runs everything | each repo runs only its own pipeline |
| Tooling | build tools that understand folders | simple, per repository |

allcsvideos (small team, services that change together) keeps the platform in one repository with CODEOWNERS per folder and path filters in CI;
split a service out when it gets its own team and release rhythm.

## Common mistakes
- **Giant pull requests.** Nobody reviews thousands of lines well. Split the work; hide unfinished parts behind a flag.
- **Rubber-stamp approvals.** An approval in seconds on a big diff is a signature, not a review. "Dismiss stale approvals" forces a fresh look after new commits.
- **Review as gatekeeping.** Blocking on taste or leaving PRs waiting for days teaches people to batch. Agree on response times; label nitpicks non-blocking.
- **Admins bypassing protection.** Make the rules apply to admins (Gitea: "administrators must follow branch protection rules"; GitHub: "do not allow bypassing"). Keep bypass lists empty or tiny and audited.
- **Tagging the wrong commit.** Pull and check before you tag; never move a pushed tag.
- **Pushing straight to main.** Protect it on the server, so the only path is a reviewed, green pull request.

## Clean up
```bash
bash lab/down.sh
rm lab/accounts.env
```

## Next
[M06-L01 · VMs vs Containers](../../docker/m06-l01-vms-vs-containers/)
