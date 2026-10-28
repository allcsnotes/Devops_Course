# M09-L05 · Jenkins and GitLab CI
> Video: Module 9, Lesson 5. Watch it first, then follow along here.

## What you'll learn
- The questions every CI tool answers: where the pipeline file lives, what starts it, who runs the work, where secrets
  live, and how services, caches and artifacts work.
- **Jenkins**: a controller, agents and plugins; configuration as code (JCasC + Job DSL); a declarative `Jenkinsfile`
  with parallel stages, a matrix, sidecar containers, credentials and `post { always { junit } }`; multibranch
  pipelines and webhooks.
- **GitLab CI**: one `.gitlab-ci.yml` with stages plus `needs`, `parallel: matrix`, services, cache vs artifacts, rules,
  and masked/protected variables; run locally with **gitlab-ci-local**.
- How the three map onto each other, the honest trade-offs, and how to migrate.

## Before you start
- Docker Desktop with about 4 GB of memory free for the lab (Jenkins alone uses about 2 GB), a terminal, a browser.
- Lessons M08-L03 and M08-L04 (this is the same Course Copilot pipeline).
- Ports `3000` (Gitea) and `8080` (Jenkins) must be free: stop the other course labs first.
- Pinned: `jenkins/jenkins:2.580.1-lts-jdk21`, `jenkins/inbound-agent:3391.va_37fa_a_305d6d-5-jdk21`,
  `gitea/gitea:28.1.0`, `docker:29.5.3-dind`, `gitlab-ci-local@4.76.1` (on `node:22.23.3-slim`), plus the pipeline's own
  images (`python:3.12.15-slim`, `python:3.13.16-slim`, `postgres:18.6-alpine3.24`, `redis:8.10.2-alpine3.23`,
  `hadolint/hadolint:v2.15.1`, Trivy `0.76.0` by digest).
- In the commands below, `L=<path-to-this-lesson-folder>`.
- Why not a real GitLab? GitLab's docs ask for 8 GB of memory at minimum (16 GB baseline) for one node, more than a
  laptop's Docker VM usually has. gitlab-ci-local runs the real `.gitlab-ci.yml` with Docker; it has no web UI and no
  merge requests. The same file also runs on gitlab.com (see step 10).

## Files in this folder
| File | What it is |
|---|---|
| `lab/up.sh`, `lab/down.sh` | Start/remove the lab: Gitea (repo + registry + webhook), a Docker-in-Docker daemon, Jenkins, agent linux-1, Asha's terminal |
| `lab/jenkins/Dockerfile`, `plugins.txt`, `casc.yaml` | The controller: LTS image + 7 plugins; JCasC: 0 executors, admin user, node linux-1, credentials, the multibranch job (Job DSL) |
| `lab/agent/Dockerfile` | The agent: inbound agent + Docker CLI (talks to the lab's own Docker daemon, never your laptop's) |
| `lab/laptop/Dockerfile` | Asha's terminal: git, Docker CLI, gitlab-ci-local |
| `repo/` | The platform repo: `copilot/`, `Jenkinsfile`, `.gitlab-ci.yml`, `.github/workflows/copilot.yml` (the GitHub Actions version from M08-L03) |
| `staged/first-try.xml` | The hook's plain Pipeline job (the wrong job type for `when { branch }`) |
| `staged/Jenkinsfile.interp` | Pitfall demo: a secret in a Groovy double-quoted string |
| `staged/anchors.gitlab-ci.yml` | Pitfall demo: YAML anchors vs `extends` |

## Follow along

1. **Start the lab** (the first run builds images and pulls a few GB):
   ```bash
   cd $L/lab
   bash up.sh
   ```
   Open Jenkins at http://localhost:8080 (user `admin`, the fake lab password `fake-lab-admin-pass-123`). **Manage
   Jenkins > Nodes**: the Built-In Node has 0 executors, `linux-1` has 2. **Credentials**: `ci-db` and `registry`,
   values shown only as stars. Read `lab/jenkins/casc.yaml`: all of that is configuration as code. Seven plugins asked
   for in `plugins.txt`; about seventy installed with their dependencies (**Manage Jenkins > Plugins > Installed**).

2. **Push the platform repo** from Asha's terminal:
   ```bash
   docker cp $L/repo cicd-laptop:/home/asha/work/src
   docker exec -u root cicd-laptop chown -R asha:asha /home/asha/work/src
   docker exec -it -u asha -w /home/asha/work cicd-laptop bash
   ```
   Inside:
   ```bash
   git clone -q http://gitea:3000/allcsvideos/platform.git && cd platform
   cp -R ../src/. .
   git add . && git commit -qm 'The same pipeline for Jenkins and GitLab CI'
   git push -q origin main
   ```

3. **The hook (staged): green, and nothing shipped.** In Jenkins: **New Item** `copilot-first-try`, type **Pipeline**,
   Definition **Pipeline script from SCM**, Git URL `http://gitea:3000/allcsvideos/platform.git`, branch `*/main`,
   script path `Jenkinsfile` (the same as `staged/first-try.xml`). **Build Now**. The console ends with:
   ```
   Stage "Image" skipped due to when conditional
   Finished: SUCCESS
   ```
   and the registry holds nothing:
   ```bash
   curl -s -H "Authorization: token $(cat ~/.gitea-token)" gitea:3000/api/v1/packages/allcsvideos | jq length
   ```
   `0`. `when { branch 'main' }` only works in a **multibranch** pipeline; a plain job never sets a branch name. Delete
   the job.

4. **Read the Jenkinsfile** (`repo/Jenkinsfile`): `agent { label 'linux && docker' }` (never the controller);
   `environment` with the image name and pip's cache inside the workspace (the workspace stays on the agent between
   builds); **Lint** with two `parallel` stages (hadolint; Python checks in a `python:3.13.16-slim` container with
   `reuseNode true`); **Unit** as a `matrix` over `PY` with `post { always { junit ... } }`; **Integration** starting
   PostgreSQL and Redis itself with `docker.image(...).withRun` (Jenkins has no `services:`), the `ci-db` login from
   `withCredentials`, and `sh '...'` in **single** quotes so the shell, not Groovy, reads the secret; **Image** only on
   `main`, with `credentials('registry')` (sets `REGISTRY_USR`/`REGISTRY_PSW`, masked), tag `sha-` + 7 characters,
   build, save, Trivy gate, `--password-stdin` login, push, and `post { always { logout; rm tar } }`.

5. **The multibranch pipeline.** Open the `course-copilot` job (created by Job DSL in `casc.yaml`) and click **Scan
   Multibranch Pipeline Now**. Indexing finds `main` and its Jenkinsfile and starts build #1. In the Pipeline Graph
   View: checkout, Lint (2 parallel branches), Unit (2 matrix cells), Integration, Image. All green (about 1 min 40 s
   in the video). The console shows `DATABASE_URL` with the password masked as `****`, and `3 passed` integration
   tests. Then:
   ```bash
   curl -s -H "Authorization: token $(cat ~/.gitea-token)" gitea:3000/api/v1/packages/allcsvideos \
     | jq -r '.[] | select(.version | startswith("sha-")) | .name + ":" + .version'
   ```
   `course-copilot:sha-<7 characters>`.

6. **The webhook: Priya's branch (staged bug).** In a second shell as Priya:
   ```bash
   docker exec -it -u priya -w /home/priya cicd-laptop bash
   git clone -q http://gitea:3000/allcsvideos/platform.git && cd platform
   git switch -qc priya/ask-speedup
   sed -i 's/words = q.lower().split()/words = q.split()/' copilot/app/main.py
   git diff
   git commit -qam 'ask: skip lowercasing the question'
   git push -u origin priya/ask-speedup
   ```
   Gitea calls Jenkins' `notifyCommit` URL the moment the push lands; Jenkins finds the new branch and builds it within
   seconds. Red: both matrix cells fail on `test_ask_ignores_case`; Integration and Image are skipped. The **Tests**
   page (drawn by `post always junit`) shows 2 failed, 6 passed. The branch list: `main` green, Priya's branch red.

7. **Pitfall: a secret in a Groovy string.** From your laptop (a branch with the integration step in double quotes):
   ```bash
   docker cp $L/staged/Jenkinsfile.interp cicd-laptop:/home/asha/work/platform/Jenkinsfile
   docker exec -u root cicd-laptop chown asha:asha /home/asha/work/platform/Jenkinsfile
   docker exec -u asha -w /home/asha/work/platform cicd-laptop bash -c \
     'git switch -qc asha/interp-demo && git diff && git commit -qam "demo: a secret in a Groovy string" && git push -q -u origin asha/interp-demo; git switch -q main'
   ```
   The build log warns: `Warning: A secret was passed to "sh" using Groovy String interpolation, which is insecure.`
   Groovy put the password into the command itself, where `ps` can see it. Single quotes, always.

8. **GitLab CI with gitlab-ci-local.** Read `repo/.gitlab-ci.yml`: `stages`, `variables`, `default` (image,
   `before_script`, cache keyed on the requirements files), `needs: []` to start at once, `parallel: matrix`,
   `artifacts: reports: junit` with `when: always`, `services` with aliases, a `docker:29.5.3-dind` service for the
   image build, `rules` for the default branch, and an artifact (`copilot.tar`, 1 hour) passed to `scan` and `push`.
   As Asha in `~/work/platform`:
   ```bash
   git switch -q main && git pull -q
   gitlab-ci-local --version
   gitlab-ci-local --list
   time gitlab-ci-local
   ```
   `--list` shows eight jobs and the `needs` graph (build waits for hadolint and integration, push for build and scan).
   The run ends with every job `PASS` and `pipeline finished in` about 2.3 min. The tag is `sha-` + **8** characters
   (`CI_COMMIT_SHORT_SHA`); the Jenkinsfile used 7: same commit, different tag. `CI_REGISTRY*` come from
   `~/.gitlab-ci-local/variables.yml` (outside the repo); on GitLab they are predefined for every project.

   Priya's branch:
   ```bash
   git fetch -q && git switch -q priya/ask-speedup
   git log --oneline -1
   gitlab-ci-local
   ```
   Both unit jobs fail (`1 failed, 3 passed`), integration never starts (it needs unit), and there are no image jobs
   at all (rules: default branch only).

9. **Pitfall: YAML anchors.** From your laptop:
   ```bash
   docker exec -u asha cicd-laptop mkdir -p /home/asha/work/anchors
   docker cp $L/staged/anchors.gitlab-ci.yml cicd-laptop:/home/asha/work/anchors/.gitlab-ci.yml
   docker exec -u root cicd-laptop chown -R asha:asha /home/asha/work/anchors
   docker exec -u asha -w /home/asha/work/anchors cicd-laptop bash -c 'git init -q && git add . && git commit -qm demo && gitlab-ci-local --preview'
   ```
   `unit-anchor` lost both pip variables (an anchor copies top-level keys only, so the job's own `variables` replaced
   them); `unit-extends` kept them (`extends` merges nested hashes). Anchors also don't work across included files.

10. **Optional: on real GitLab.** Push `repo/` to a new project on gitlab.com: the same `.gitlab-ci.yml` runs on GitLab's
    hosted runners, draws the pipeline graph, shows the JUnit results in the merge request, and `CI_REGISTRY`,
    `CI_REGISTRY_USER` and `CI_REGISTRY_PASSWORD` are predefined (the `--insecure-registry=gitea:3000` flag in the dind
    services is only for this lab and can be removed). Real secrets go in **Settings > CI/CD > Variables**: **Masked**
    (shown as `[MASKED]`, at least 8 characters, one line) and **Protected** (only on protected branches and tags).
    GitLab's docs warn that masking is not a guaranteed protection.

**The map** (from the video):

| | GitHub Actions | GitLab CI | Jenkins |
|---|---|---|---|
| File | `.github/workflows/*.yml` | `.gitlab-ci.yml` | `Jenkinsfile` |
| Trigger | `on:` | every push, filtered by `rules` | webhook or polling |
| Unit of work / step | job / step | job / script line | stage / steps |
| Runs on | runner | GitLab Runner | agent |
| Secrets | `secrets.X` | masked + protected CI/CD variables | credentials |
| Cache | `actions/cache` | `cache:` | the workspace, or a plugin |
| Artifacts | `upload-artifact` | `artifacts:` | `archiveArtifacts`, `junit` |
| Services | `services:` | `services:` | sidecar containers you start |
| Matrix | `strategy.matrix` | `parallel: matrix` | `matrix` directive |

Usually you use the CI that comes with your code host; Jenkins where it already runs or where nothing hosted is
allowed. GitHub Actions Importer audits, forecasts, dry-runs and migrates pipelines from Jenkins and GitLab (GitHub aims
for about 80% conversion; inspect every result). Migrate one pipeline at a time, run old and new side by side, map the
secrets first, and look for the native feature instead of copying plugins line by line.

## Common mistakes
- **Plugin sprawl and unpatched controllers.** 7 plugins became about 70. Update on a schedule, remove what you don't
  use, never expose an old Jenkins to the internet.
- **Running builds on the controller.** Keep the built-in node at 0 executors.
- **Secrets in Groovy strings.** Single quotes, always.
- **YAML anchors** copy top-level keys only; use `extends`.
- **Assuming one tool's behaviour in another.** `when { branch }` needs multibranch; GitLab's short SHA has 8 characters;
  a Jenkins workspace survives between builds while GitHub and GitLab jobs start clean.

## Clean up
```bash
cd $L/lab
bash down.sh
```

## Next
[M09-B01 · End-to-End Pipeline](../m09-b01-end-to-end-pipeline/)
