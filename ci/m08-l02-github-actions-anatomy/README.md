# M08-L02 · GitHub Actions Anatomy
> Video: Module 8, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- The six words of GitHub Actions, nested like boxes: **workflow**, **trigger** (`on`), **job**, **step**,
  **runner** (`runs-on`), **action** (`uses`).
- Triggers: branch, path and tag filters, `pull_request`, a manual run with inputs (`workflow_dispatch`), and a cron
  `schedule`.
- Jobs: parallel by default, ordered with `needs`, passing data with job outputs, switched on or off with `if`.
- Inside a job: `run` vs `uses`, `with`, `env` at three levels, `working-directory`, `shell`, contexts and
  expressions, `GITHUB_OUTPUT` and `GITHUB_ENV`.
- Actions: pin third-party actions to a commit SHA, write your own composite action; plus `concurrency` and
  `timeout-minutes`.

## Before you start
- Your `allcsvideos-ops` repo on GitHub from [M08-L01](../m08-l01-what-ci-is/), with its first
  `.github/workflows/ci.yml` (three runs so far). Git, VS Code, and optionally the GitHub CLI `gh`.
- In the commands below, `L=<path-to-this-lesson-folder>` (for example
  `L=~/Devops_Course/ci/m08-l02-github-actions-anatomy`). Run everything else inside `~/allcsvideos-ops`.
- Prefer to stay offline? The video ran every change on a local Gitea with Gitea Actions:
  [`../m08-l01-what-ci-is/gitea-lab/`](../m08-l01-what-ci-is/gitea-lab/README.md). On Gitea, workflows live in
  `.gitea/workflows/` and jobs run as root (see that README).

## Files in this folder
| File | What it is |
|---|---|
| `.github/workflows/ci.yml` | The final `ci` workflow: filters, lint -> test -> build -> release, pinned actions, concurrency, timeouts |
| `.github/workflows/nightly.yml` | The final `nightly` workflow: hc dry run at 02:00 IST, or by hand with an input |
| `.github/actions/hc-lint/action.yml` | A composite action in the repo: syntax-checks the hc shell and Python files |
| `stages/01-ci-oops.yml` | Staged mistake: one step indented one space too little |
| `stages/02-ci-filters.yml` | `ci` with branch and path filters |
| `stages/03-nightly-every-5-min.yml` | First `nightly`, scheduled every 5 minutes for the demo |
| `stages/04-ci-parallel.yml` | `lint` and `test` side by side (parallel) |
| `stages/05-ci-needs-outputs.yml` | `needs`, outputs, `if`, env levels, contexts, `GITHUB_OUTPUT` / `GITHUB_ENV` |
| `stages/06-ci-pinned-composite.yml` | Actions pinned to commit SHAs, lint via the composite action |
| `stages/hc-lint-v1.action.yml` | First version of the composite action (it misses one file) |
| `extras/.github/...` | For a scratch repo: a reusable workflow, a composite action with an output, a 1-minute timeout |

## Follow along

1. **The hook: every push runs everything.** Add one line of docs and push:
   ```bash
   cd ~/allcsvideos-ops
   git pull
   echo 'CI: every push runs the hc tests (.github/workflows/ci.yml)' >> README.md
   git commit -am 'README: mention CI'
   git push
   ```
   The whole `test` job runs for a README line. The workflow said `on: push`, so: every push.

2. **Read the file: five keys.** `name` (shown in the Actions tab, and the first part of every check name:
   `ci / test`), `on` (the triggers), `jobs` (job IDs to jobs), `runs-on` (the runner label), `steps` (`uses` runs an
   action, `run` runs a shell script; `|` makes the indented lines below one multi-line string).

   Two YAML traps, if you have PyYAML (`python3 -m pip install pyyaml`):
   ```bash
   head -3 .github/workflows/ci.yml
   python3 -c 'import yaml; print(yaml.safe_load(open(".github/workflows/ci.yml")).keys())'
   python3 -c 'import yaml; print(yaml.safe_load("version: 3.10"))'
   python3 -c 'import yaml; print(yaml.safe_load("version: \"3.10\""))'
   ```
   You should see `dict_keys(['name', True, 'jobs'])` (YAML 1.1 reads a bare `on` as `true`; GitHub handles it, your
   own scripts may not), then `{'version': 3.1}` and `{'version': '3.10'}`: always quote versions.

3. **Break the indentation, on a throwaway branch.**
   ```bash
   git switch -c asha/yaml-oops
   cp $L/stages/01-ci-oops.yml .github/workflows/ci.yml
   git diff
   git commit -am 'ci: tidy the test step'
   git push -u origin asha/yaml-oops
   ```
   In **Actions** the run fails at once with no jobs at all: **Invalid workflow file**, with a YAML syntax error
   around the step you moved. Indentation is the structure: spaces only, never tabs, every dash of a list lined up.
   ```bash
   git switch main
   git branch -D asha/yaml-oops
   git push origin --delete asha/yaml-oops
   ```

4. **Narrow the trigger: branch and path filters.**
   ```bash
   cp $L/stages/02-ci-filters.yml .github/workflows/ci.yml
   git diff
   git commit -am 'ci: run only for hc and workflow changes, on main and PRs'
   git push
   ```
   That push changed a file under `.github/`, so it matches and the run passes. Now a docs-only push:
   ```bash
   echo 'Docs: hc/README.md' >> README.md
   git commit -am 'README: link the toolkit docs'
   git push
   ```
   No run. In **Code > Commits** that commit has no check mark at all: CI never started.

5. **A pull request.** Priya adds tests for both edges of `rate()`:
   ```bash
   git switch -c priya/rate-edges
   ```
   In `hc/tests/run.sh`, right after the line `check "rate 95 is CRIT" ...`, add:
   ```bash
   check "rate 89 is WARN" WARN "$(rate 89 80 90)"
   check "rate 90 is CRIT" CRIT "$(rate 90 80 90)"
   ```
   ```bash
   git diff
   git commit -am 'tests: cover both edges of rate()'
   git push -u origin priya/rate-edges
   ```
   No run: `branches: [main]` means pushes to other branches don't trigger it. Open the pull request (web UI, or):
   ```bash
   gh pr create --base main --head priya/rate-edges \
     --title 'tests: cover both edges of rate()' \
     --body 'Two boundary tests for rate(): 89 is WARN, 90 is CRIT.'
   ```
   That is a `pull_request` event. The PR page shows the check **ci / test (pull_request)** passing, and its log ends
   with `15 passed, 0 failed`. On GitHub the pull request run tests a preview **merge** of the branch into main
   (Gitea tested the branch's head commit). Merge it (`gh pr merge --merge`), then:
   ```bash
   git switch main && git pull
   ```
   The merge is a push to main that touches `hc/`, so `ci` checks main again.

6. **Manual runs and schedules: `nightly.yml`.**
   ```bash
   cp $L/stages/03-nightly-every-5-min.yml .github/workflows/nightly.yml
   git add .github/workflows/nightly.yml
   git commit -m 'nightly: hc dry run on a schedule, or by hand'
   git push
   ```
   `workflow_dispatch` adds a **Run workflow** button (Actions > nightly) with `config` as a drop-down. Start it with
   `warn`:
   ```bash
   gh workflow run nightly.yml -f config=warn
   gh run watch
   ```
   You should see hc find a warning and exit 1, so the job fails (the input really reached the step):
   ```
   event: workflow_dispatch, config: warn
   WARN  disk /                   ...% used
   ...
   dry run: would alert OK -> WARN
   Error: Process completed with exit code 1.
   ```
   `${{ inputs.config || 'ok' }}` falls back to `ok` when there is no input, as on a schedule. Wait for a scheduled
   run (`event: schedule, config: ok`, every check OK). On GitHub the shortest interval is 5 minutes and scheduled
   runs are often delayed under load, so it can take a while. Then set the real schedule, `30 20 * * *` (cron is in
   UTC, so 02:00 in India):
   ```bash
   cp $L/.github/workflows/nightly.yml .github/workflows/nightly.yml
   git diff
   git commit -am 'nightly: back to 02:00 IST every night'
   git push
   ```
   Scheduled runs only run on the default branch, and in a public repo they are disabled after 60 days without
   activity.

7. **Jobs run in parallel.** Add a `lint` job next to `test` (it installs Python 3.13 and syntax-checks every
   script):
   ```bash
   cp $L/stages/04-ci-parallel.yml .github/workflows/ci.yml
   git commit -am 'ci: a lint job next to the tests'
   git push
   ```
   The run graph shows `lint` and `test` side by side, each on its own fresh runner. `lint` takes longer: most of it
   is installing Python. (On the Gitea lab, `docker ps` shows two job containers at once.)

8. **Order, outputs, `if`, and a real tag.**
   ```bash
   cp $L/stages/05-ci-needs-outputs.yml .github/workflows/ci.yml
   git commit -am 'ci: lint, then test, then build; release only on tags'
   git push
   ```
   Four jobs, three dependencies: `lint` -> `test` -> `build` -> `release`, and `release` is **skipped** (this push
   wasn't a tag). In the `build` log you should see:
   ```
   commit: <the full commit SHA>
   ref:    main
   runner: Linux
   STAGE=step
   ...
   -rw-r--r-- ... 7928 ... hc-1.3.0-<short sha>.tar.gz   (about 8 KB)
   ```
   `STAGE=step`: the most specific `env` level wins. The "Name the package" step shows as `v=1.3.0`: expressions are
   filled in before the script runs. Now bump the version and tag it (macOS: use `sed -i ''`):
   ```bash
   sed -i 's/^readonly VERSION=1.3.0/readonly VERSION=1.4.0/' hc/bin/hc
   git commit -am 'hc: version 1.4.0'
   git push
   git tag -a v1.4.0 -m 'hc 1.4.0'
   git push origin v1.4.0
   ```
   Two runs: one for the push to main, one for the tag (path filters don't apply to tag pushes). In the tag run all
   four jobs are green and `release` prints:
   ```
   release hc 1.4.0 from tag v1.4.0
   ```
   The version came from the `build` job's output. Lesson 4 replaces this stand-in with real images.

9. **Pin actions, and a composite action of your own.** Tags move:
   ```bash
   git ls-remote https://github.com/actions/checkout refs/tags/v4 refs/tags/v4.4.0
   ```
   You see the SHAs both tags point to today (in the video: both `11d5960a...` for v4 and v4.4.0). Pin to the full
   SHA, with the version as a comment, and move the lint script into `.github/actions/hc-lint/` (first version):
   ```bash
   mkdir -p .github/actions/hc-lint
   cp $L/stages/hc-lint-v1.action.yml .github/actions/hc-lint/action.yml
   cp $L/stages/06-ci-pinned-composite.yml .github/workflows/ci.yml
   git add .github
   git commit -m 'ci: pin actions to commit SHAs, lint via a composite action'
   git push
   ```
   The workflow uses it with `uses: ./.github/actions/hc-lint`, **after** the checkout (the action lives in the
   repo). Each `run` step in a composite action must name its `shell`. It passes, but the lint log says
   `shell ok: 4 scripts`; the old inline lint checked 5. `hc/lib/checks.sh` has no `#!` line, so it was skipped.
   Fix it:
   ```bash
   cp $L/.github/actions/hc-lint/action.yml .github/actions/hc-lint/action.yml
   git diff
   git commit -am 'hc-lint: also check sourced .sh files'
   git push
   ```
   Now: `shell ok: 5 scripts`. Read the CI log, not just the green tick.

10. **Concurrency and timeouts.**
    ```bash
    cp $L/.github/workflows/ci.yml .github/workflows/ci.yml
    git diff
    git commit -am 'ci: cancel superseded runs, time out stuck jobs'
    git push
    ```
    Every job now has `timeout-minutes: 10` (the default limit on GitHub is 360 minutes), and runs share one
    `concurrency` group per ref with `cancel-in-progress: true`. Push twice in a row (macOS: `sed -i ''`):
    ```bash
    sed -i 's/^# hc - a server/# hc: a server/' hc/README.md
    git commit -am 'hc README: a clearer title' && git push
    echo 'Run the tests: bash tests/run.sh' >> hc/README.md
    git commit -am 'hc README: how to run the tests' && git push
    ```
    The first run is **cancelled** part-way; the run for the newest commit passes.

11. **Optional: reusable workflows and a timeout, in a scratch repo.** Create an empty repo (for example
    `actions-sandbox`), copy `extras/.github` into it and push. The `call` job runs `reuse.yml` (`on: workflow_call`)
    and `after` prints `reusable said built-hc`; `py` prints `composite said hello asha`; `slow` sleeps 90 s with
    `timeout-minutes: 1` and fails after about a minute, on purpose.

## Common mistakes
- **Workflows that run on every change.** Filter by branch and path, but never filter out files your tests depend on.
- **Unpinned actions.** A tag can move under you; pin third-party actions to a full commit SHA.
- **Secrets in logs.** The runner masks values it knows are secret (the checkout's auth header shows as `***`); a
  secret it doesn't know, or one echoed in another form, prints in clear. Lesson 5 covers secrets.
- **`pull_request_target`.** It runs with the base repo's permissions and secrets, even for a fork's PR. Avoid it unless
  you need it, and never check out the PR's code in it.
- **YAML indentation.** One space broke step 3. Use an editor with YAML support (VS Code + the GitHub Actions extension).
- Self-hosted runners on **public** repos: anyone can open a PR and run code on your machine. Use GitHub-hosted runners.

## Clean up
Keep `allcsvideos-ops` for the next lesson. The scheduled `nightly` runs once a night; to stop it, disable it
(Actions > nightly > ... > Disable workflow, or `gh workflow disable nightly.yml`). Delete the optional scratch repo:
```bash
gh repo delete <your-user>/actions-sandbox
```

## Next
[M08-L03 · Build, Test and Lint](../m08-l03-build-test-and-lint/)
