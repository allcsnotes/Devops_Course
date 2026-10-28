# M08-L03 · Build, Test and Lint
> Video: Module 8, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- Order a pipeline as a **fail-fast funnel**: lint and format (seconds), unit tests, integration tests, then the build.
  Each stage is a gate that needs the one before.
- Lint gates for a Python service and its Dockerfile (ruff, mypy, hadolint) and for Bash (shellcheck).
- Cache dependencies with `actions/cache`, keyed on the requirements hash, and measure before you optimise.
- Matrix builds (`strategy.matrix`, `fail-fast`, `max-parallel`, `include`/`exclude`) and test reports as artifacts.
- Real PostgreSQL and Redis as **service containers**, why they need health checks, and how flaky tests happen.
- Make every stage a **required status check**, so a red lint blocks the merge.

## Before you start
- Your `allcsvideos-ops` repo on GitHub from [M08-L01](../m08-l01-what-ci-is/) and
  [M08-L02](../m08-l02-github-actions-anatomy/).
- Python 3.12 or 3.13 on your laptop (to run Copilot, ruff and pytest locally), Git, VS Code, optionally `gh`.
- In the commands below, `L=<path-to-this-lesson-folder>`. Run everything else inside `~/allcsvideos-ops`.
- Branch protection with required checks is free on **public** repos (private repos need a paid plan).
- Prefer to stay offline? The video ran on the local Gitea lab:
  [`../m08-l01-what-ci-is/gitea-lab/`](../m08-l01-what-ci-is/gitea-lab/README.md) (the recording also set the runner
  to `capacity: 3` and switched its cache server on).

## Files in this folder
| File | What it is |
|---|---|
| `starter/copilot/` | Course Copilot (FastAPI): app, unit tests, integration tests, DB migration, Dockerfile, pinned requirements |
| `.github/workflows/copilot.yml` | Copilot pipeline: `lint` -> `unit` (py3.12, py3.13) -> `integration` (Postgres + Redis services) |
| `.github/workflows/hc.yml` | hc pipeline: `shellcheck` -> `test` |
| `changes/greet-by-name/copilot/app/main.py` | Priya's feature, with the typo `nmae` (staged bug) |
| `changes/fix-lint/copilot/Dockerfile` | Fix for hadolint DL3045: `WORKDIR /build` in the build stage |
| `changes/test-version/test_health_append.py` | Rahul's extra unit test (appended to `copilot/tests/test_health.py`) |
| `stages/copilot-1-no-healthchecks.yml` | Staged: services without health checks, Postgres at `--cpus 0.25` |
| `stages/copilot-2-healthchecks-busy.yml` | Staged: health checks back, still on the squeezed Postgres |

## Follow along

1. **Move Course Copilot into the repo** and set it up locally:
   ```bash
   cd ~/allcsvideos-ops && git pull
   cp -R $L/starter/copilot ./copilot
   git add copilot
   git commit -m 'copilot: move the Course Copilot service into this repository'
   git push
   cd copilot
   python3 -m venv .venv && . .venv/bin/activate
   pip install -r requirements.txt -r requirements-dev.txt
   deactivate; cd ..
   ```
   Tool versions are pinned in `requirements-dev.txt` (ruff 0.17.1, mypy 2.4.0, pytest 9.1.1): the same on every laptop
   and in CI.

2. **The hook: a green check that checks nothing.** Priya greets students by name:
   ```bash
   cp $L/changes/greet-by-name/copilot/app/main.py copilot/app/main.py
   git diff --stat
   git commit -am 'copilot: greet the student by name'
   git push
   ```
   Your current CI only knows about `hc` (with lesson 2's path filters it does not even start for this change).
   Nothing installed Copilot's dependencies, linted it or ran its tests. Run it like Rahul does:
   ```bash
   cd copilot && . .venv/bin/activate
   uvicorn app.main:app --port 8000
   ```
   In a second terminal:
   ```bash
   curl -s "localhost:8000/ask?q=docker"; echo
   curl -s "localhost:8000/ask?q=cooking&name=Lukas"; echo
   ```
   You should see `{"answer":"Try the DevOps course."}`, then `Internal Server Error` (the uvicorn log says
   `NameError: name 'nmae' is not defined`). Stop uvicorn with Ctrl+C. The repo already has a test for this path:
   ```bash
   pytest -q -m "not integration"
   deactivate; cd ..
   ```
   `1 failed`. Stop the line:
   ```bash
   git revert --no-edit HEAD
   git push
   ```

3. **The real pipeline: two workflows, one per part.** Each has a path filter (`copilot.yml` only runs when
   `copilot/**` or the workflow changes; `hc.yml` the same for `hc/**`). Push runs only on main; pull requests run on
   every branch, so a branch is tested once, in its PR.
   ```bash
   cp $L/.github/workflows/copilot.yml $L/.github/workflows/hc.yml .github/workflows/
   git rm -q .github/workflows/ci.yml
   git add .github/workflows
   git status --short
   git commit -m 'ci: lint, unit and integration tests for copilot, shellcheck for hc'
   git push
   ```
   Read `copilot.yml`: `lint` runs hadolint as a Docker action straight from its pinned image, then Python 3.13,
   `ruff check`, `ruff format --check` (changes nothing, fails if it would) and `mypy`. `hc.yml` runs shellcheck 0.11.0
   the same way, then the hc tests.

   Both workflows go **red** within seconds. Copilot `lint`:
   ```
   copilot/Dockerfile:8 DL3045 warning: `COPY` to a relative destination without `WORKDIR` set.
   copilot/Dockerfile:14 DL3045 warning: `COPY` to a relative destination without `WORKDIR` set.
   ```
   and `unit` and `integration` are **skipped**: fail fast. hc `shellcheck`:
   ```
   SC1091 (info): Not following: lib/checks.sh was not specified as input (see shellcheck -x).
   ```
   New gates find old problems. Fix them instead of switching the rule off:
   In `hc/tests/run.sh`, add this line directly above `source lib/checks.sh` (it tells shellcheck where the sourced
   file is, like `hc/bin/hc` already does):
   ```bash
   # shellcheck source-path=SCRIPTDIR source=../lib/checks.sh
   ```
   ```bash
   cp $L/changes/fix-lint/copilot/Dockerfile copilot/Dockerfile
   git diff
   git commit -am 'Fix lint findings: WORKDIR in the build stage, shellcheck source directive'
   git push
   ```
   Both green: copilot runs `lint`, `unit (py3.12)`, `unit (py3.13)`, then `integration`.

4. **Caching.** Every job starts fresh, so every job downloads the same packages. The `actions/cache` step keeps pip's
   download folder (`~/.cache/pip`). The key is `pip-<OS>-py<version>-<hash of copilot/requirements*.txt>`: change a
   requirement and you get a fresh cache. `restore-keys` is the prefix fallback. In the first green run's logs:
   ```
   Cache not found for input keys: pip-Linux-py3.13-3096c866..., pip-Linux-py3.13-
   Cache saved with key: pip-Linux-py3.13-3096c866...
   ```
   A later job with the same key gets `Cache hit for: pip-Linux-py3.13-...`: it's about contents, not which job made it.
   Now Rahul adds one unit test:
   ```bash
   cat $L/changes/test-version/test_health_append.py >> copilot/tests/test_health.py
   git diff
   git commit -am 'copilot: test the version in /health'
   git push
   ```
   Only `copilot` runs (`hc` is skipped by its path filter). Every cache step hits, and says:
   ```
   Cache hit occurred on the primary key pip-Linux-py3.13-..., not saving cache.
   ```
   An exact hit is never written again. Compare the `pip install` step times between the cold and the warm run (the
   video: lint 10 s -> 5 s, unit on 3.12 16 s -> 7 s). On GitHub-hosted runners `setup-python` is fast because a few
   Python versions are preinstalled; on the Gitea lab it downloaded Python every time. Measure first. Never cache
   secrets, build outputs or test results.

5. **Matrix and test reports.** `unit` runs once per `matrix.python` (`"3.12"`, `"3.13"`): the run graph groups them as
   **Matrix: unit**, 2 jobs, started together. `fail-fast: false` keeps one version's failure from cancelling the other
   (the default `true` would cancel). `max-parallel` caps how many run at once; `include`/`exclude` add or remove
   combinations. Every dimension multiplies (3 OS x 4 Pythons x 2 DBs = 24 jobs per push; GitHub caps a matrix at 256).
   pytest writes `reports/junit.xml` and `reports/coverage.xml`; `actions/upload-artifact@v4` with `if: always()`
   uploads them even when tests fail. The run page lists **test-report-py3.12** and **test-report-py3.13** (names
   must be unique per run in v4; v3 was turned off on GitHub on January 30, 2025).

6. **Service containers.** `integration` starts `postgres:18.6-alpine3.24` and `redis:8.10.2-alpine3.23` (the same pins
   as Module 7) with health checks (`pg_isready`, `redis-cli ping`); the runner waits until they are healthy. The
   migration step runs `psql` from the postgres image (a container action, so it reaches the service as `postgres`);
   pytest runs on the runner VM and reaches the services on `localhost` through the mapped ports. (On Gitea the job
   itself ran in a container, so the URLs used the service names.) The password is a fake one for a throwaway DB.
   You should see:
   ```
   CREATE TABLE
   INSERT 0 3
   ...
   3 passed, 4 deselected
   ```

7. **Break it, on purpose: services without health checks on a busy machine.**
   ```bash
   cp $L/stages/copilot-1-no-healthchecks.yml .github/workflows/copilot.yml
   git diff
   git commit -am 'staged: no service health checks, and a busy CI machine'
   git push
   ```
   In the video, `integration` failed: the runner said `postgres service is healthy` 0.6 s after start (with no health
   check it has nothing to wait for), and the migration hit
   ```
   psql: error: connection to server at "postgres" (...), port 5432 failed: Connection refused
   ```
   Re-run only that job a few times (**Re-run jobs > Re-run failed jobs**, or `gh run rerun <run-id> --failed`).
   On GitHub's fast VMs it may pass some or all of the time: same code, different result depending on how busy the
   machine is. That is a flaky test, and the bug is in the pipeline. The fix, still on the squeezed machine:
   ```bash
   cp $L/stages/copilot-2-healthchecks-busy.yml .github/workflows/copilot.yml
   git diff
   git commit -am 'ci: wait for healthy services (still on the busy machine)'
   git push
   ```
   Now the log says `postgres service is starting`, then healthy a few seconds later, then the migration: green.
   Remove the staged CPU limit:
   ```bash
   cp $L/.github/workflows/copilot.yml .github/workflows/copilot.yml
   git commit -am 'ci: remove the staged CPU limit'
   git push
   ```

8. **Make the checks required.** On GitHub: repo **Settings > Branches > Add branch protection rule** (or **Rules >
   Rulesets**) for `main`: **Require a pull request before merging**, **Require status checks to pass**, and add the
   four checks `lint`, `unit (py3.12)`, `unit (py3.13)`, `integration` (GitHub lists checks it has seen recently; they
   appear on PRs as `copilot / lint (pull_request)` and so on). Tick **Do not allow bypassing the above settings**.

9. **Priya's feature comes back, as a pull request.**
   ```bash
   git pull
   git switch -c greet-by-name
   git cherry-pick ':/^copilot: greet the student'
   git push -u origin greet-by-name
   gh pr create --base main --head greet-by-name --title 'copilot: greet the student by name' \
     --body 'The fallback answer now greets the student by name: /ask?q=...&name=Lukas. Default: there.'
   ```
   `lint` fails within seconds with `F821 Undefined name 'nmae'`; the other three are skipped. The PR says some
   required checks failed and the merge button is blocked. Run the same tools locally:
   ```bash
   cd copilot && . .venv/bin/activate
   ruff check .
   ```
   Fix the typo (`{nmae}` -> `{name}` in `app/main.py`), then:
   ```bash
   ruff check .
   ruff format --check .
   ruff format .
   pytest -q -m "not integration"
   ```
   You should see `All checks passed!`, then `1 file would be reformatted` (spaces around `=`, one string joined),
   `1 file reformatted`, and `5 passed, 3 deselected`. Push to the same branch:
   ```bash
   cd ..
   git diff
   git commit -am 'copilot: fix the typo in name, ruff format'
   git push
   deactivate
   ```
   All four checks green: **All checks have passed**, and the PR can be merged. Merge it (`gh pr merge --merge
   --delete-branch`).

## Common mistakes
- **Caching the wrong thing.** A key without the lock file hash restores a stale cache, and an exact hit is never
  saved again, so it stays stale.
- **Over-broad matrices.** Every dimension multiplies jobs and minutes. Test what you really ship.
- **Services without health checks.** The runner says healthy at once and your tests race the database.
- **Tests that depend on order or time.** Each test sets up its own data (the Redis fixture runs `flushdb`); pass the
  clock in. Quarantine a flaky test honestly (owner, issue, deadline), never retry until green.
- **Ignoring lint "just this once".** Fix the finding, or disable one rule on one line with a comment saying why.
- **Required checks behind path filters.** A workflow skipped by its path filter leaves its required checks pending,
  so the PR waits forever. Only require checks that always run, or add a small gate job that always runs.

## Clean up
Keep the repo for the next lessons. Locally, stop uvicorn if still running and optionally remove the venv:
```bash
rm -rf ~/allcsvideos-ops/copilot/.venv
```
Workflow artifacts (test reports) expire on their own (90 days by default); delete them earlier on the run page.

## Next
[M08-L04 · Building and Pushing Images](../m08-l04-building-and-pushing-images/)
