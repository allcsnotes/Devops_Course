# M08-L01 · What CI Is
> Video: Module 8, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- Why "integration hell" happens: integration pain grows with the time between merges.
- Continuous integration as a **practice** (merge into main at least daily, every commit verified by an automated
  build and tests), and the CI server as the tool that makes it cheap.
- The five CI habits: integrate daily, build and test every commit, keep the build under about ten minutes, fix a
  broken build at once (or revert), keep main releasable.
- What a CI server does: watch the repo, trigger a workflow, hand the job to a runner, run it in a clean environment,
  report a status back to the commit and pull request.
- The difference between continuous integration, continuous delivery and continuous deployment.

## Before you start
- Git, a terminal, VS Code, and a free **GitHub** account (a public repository gets free GitHub Actions minutes).
- Optional: the [GitHub CLI](https://cli.github.com/) `gh` (used for a few handy commands below; the web UI works too).
- The repository used in this module is **allcsvideos-ops**, the team's ops repo with the `hc` health-check toolkit
  from Module 3 and the Git history from Module 5. A ready copy of it (as Module 5 left it, version 1.3.0) is in
  [`starter/allcsvideos-ops/`](starter/allcsvideos-ops/).
- Prefer to stay offline? The video used a local **Gitea** server with Gitea Actions. You can run the same thing:
  see [`gitea-lab/`](gitea-lab/README.md).

## Files in this folder
| File | What it is |
|---|---|
| `.github/workflows/ci.yml` | The first workflow: run the hc tests on every push and pull request |
| `starter/allcsvideos-ops/` | The allcsvideos-ops repo to push to your own GitHub account (hc toolkit + tests) |
| `gitea-lab/` | Optional local CI lab (Gitea 28.1.0 + Gitea runner 5.1.1 in Docker), used by Modules 8 and 9 |

## Follow along

1. **Make your own copy of allcsvideos-ops** (run from this lesson folder):
   ```bash
   cp -R starter/allcsvideos-ops ~/allcsvideos-ops
   cd ~/allcsvideos-ops
   git init -b main
   git add .
   git commit -m "allcsvideos-ops: hc toolkit 1.3.0"
   git tag -a v1.3.0 -m "hc 1.3.0"
   ```

2. **Create an empty GitHub repository and push to it.** On github.com: **New repository**, name
   `allcsvideos-ops`, **Public**, no README. Then:
   ```bash
   git remote add origin https://github.com/<your-user>/allcsvideos-ops.git
   git push -u origin main
   git push origin --tags
   ```
   (With the GitHub CLI instead: `gh repo create allcsvideos-ops --public --source . --push`.)

   Open the **Actions** tab of the repository: there are no workflows yet. On GitHub you don't need to set up a
   runner: GitHub-hosted runners give each job a newly provisioned virtual machine.

3. **Add the workflow.** The file goes in `.github/workflows/` (Gitea reads `.gitea/workflows/`; same YAML).
   ```bash
   mkdir -p .github/workflows
   cp <path-to-this-lesson>/.github/workflows/ci.yml .github/workflows/ci.yml
   cat .github/workflows/ci.yml
   ```
   Read it top to bottom: `name: ci`; `on: [push, pull_request]` runs it on every push and every pull request; one
   job `test`; `runs-on: ubuntu-latest`; step one `actions/checkout@v4` fetches this exact commit; step two runs
   the hc tests.

4. **Commit and push. The push is the trigger.**
   ```bash
   git add .github/workflows/ci.yml
   git commit -m "ci: run the hc tests on every push"
   git push
   ```
   Open **Actions**: run #1 of `ci` starts within seconds. Open the job `test` and expand **Run the hc tests**.
   You should see:
   ```
   ok    rate 79 is OK
   ok    rate 80 is WARN
   ok    rate 95 is CRIT
   ok    worst is CRIT
   ...
   ok    CRIT: exit 2
   13 passed, 0 failed
   ```
   On the repository's main page, the latest commit now has a green check: the status was reported back.
   With the CLI: `gh run list` and `gh run view --log`.

5. **Break it, on purpose.** Priya decides a check should warn only *above* its threshold, not *at* it. Open
   `hc/lib/checks.sh` in VS Code and, in `rate()`, change `>=` to `>` on the `elif` line (one character). Then:
   ```bash
   git diff
   ```
   You should see:
   ```
   -  elif (( $1 >= $2 )); then echo WARN
   +  elif (( $1 > $2 )); then echo WARN
   ```
   Commit straight to main and push (this fresh repo has no branch protection yet):
   ```bash
   git commit -am "checks: warn only above the threshold"
   git push
   ```
   Run #2 goes **red**. In its log:
   ```
   ok    rate 79 is OK
   FAIL  rate 80 is WARN: expected 'WARN', got 'OK'
   ...
   12 passed, 1 failed
   Error: Process completed with exit code 1.
   ```
   The commit list (**Code > Commits**) shows a red cross on that commit, right above the green one: which commit
   broke main, and why, within seconds.

6. **Stop the line: revert at once.**
   ```bash
   git revert --no-edit HEAD
   git push
   ```
   Run #3 is green again: three runs, three statuses, each tied to one commit. The check is named
   `ci / test (push)` (workflow name / job name (event)), the name a branch protection rule can require later.
   ```bash
   gh run list --limit 3
   ```
   If Priya still wants the new rule, it comes back with an updated test, in a pull request.

## Common mistakes
- **CI that only builds.** Green then means "it compiled", not "it works". A pipeline without tests is a slow compiler.
- **Flaky tests everyone re-runs.** One day a real failure gets re-run too. Fix it, or quarantine it with an owner and
  a deadline.
- **Slow pipelines.** Keep feedback within about ten minutes: cache, split the work, move the slowest tests later.
- **CI theatre.** A CI server and green badges, but feature branches that live for weeks. That is not continuous
  integration; merge into main at least daily.
- **A red main left red.** If a broken build is normal, nobody notices the next one. Fix or revert, in minutes.
- Putting the workflow in the wrong folder: GitHub only reads `.github/workflows/*.yml`.

## Clean up
Keep `~/allcsvideos-ops` and its GitHub repo: the next lessons build on them. To remove them completely later:
```bash
rm -rf ~/allcsvideos-ops
gh repo delete <your-user>/allcsvideos-ops      # or: repo Settings > Danger Zone > Delete this repository
```
If you used the optional Gitea lab: `bash gitea-lab/down.sh`.

## Next
[M08-L02 · GitHub Actions Anatomy](../m08-l02-github-actions-anatomy/)
