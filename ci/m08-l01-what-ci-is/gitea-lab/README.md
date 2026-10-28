# Optional: a local CI lab with Gitea Actions

The videos in Modules 8 and 9 recorded CI on a self-hosted **Gitea** server with **Gitea Actions**, all in Docker.
You do **not** need it: every lesson folder works on real GitHub Actions. Use this lab if you want to practise
offline, without a GitHub account, or want to see the runner and its job containers with `docker ps`.

Gitea Actions runs the same workflow syntax as GitHub Actions. Gitea reads workflows from `.gitea/workflows/`, and
falls back to `.github/workflows/` when a repository has no `.gitea/workflows/`, so the lesson files work as they are.

## What runs

| Container | Image (pinned) | Role |
|---|---|---|
| `gitea` | `gitea/gitea:28.1.0` | Git server, web UI, REST API and Gitea Actions (the CI server). `http://localhost:3000` |
| `gitea-runner` | `gitea/runner:5.1.1` | The runner (formerly called `act_runner`). Has the Docker socket so it can start job containers. |
| `GITEA-ACTIONS-TASK-<n>-...` | `gitea/runner-images:ubuntu-24.04-v26.10.01` | One fresh job container per job, removed when the job ends. |

All on the Docker network `ci-lab`, with volumes `gitea-data` and `gitea-runner-data`. Needs Docker Desktop and
internet (images, and `actions/checkout@v4` is fetched from github.com).

## Start it

```bash
bash up.sh
```

It creates a lab-only admin **`ci-admin`** with the fake password **`change-me-123`** (fine for a throwaway lab on
your laptop, never reuse it), an empty repository `ci-admin/allcsvideos-ops`, and registers the runner with a token
from `gitea actions generate-runner-token` (a secret, so the script never prints it). You should see:

```
level=info msg="Runner registered successfully."
... runner: runner-01, with version: v5.1.1, with labels: [ubuntu-latest], declare successfully
```

Open http://localhost:3000, sign in, and check **Site Administration > Actions > Runners**: `runner-01` is Idle.

## Push a repository to it

```bash
cd ~/allcsvideos-ops                     # your repo from the lesson
git remote add gitea http://localhost:3000/ci-admin/allcsvideos-ops.git
git push -u gitea main                   # user ci-admin, password change-me-123
```

Then open the **Actions** tab of the repository.

## Differences from GitHub

- Job containers run as **root**. Tools that refuse root (like `hc` in M08-L01) need the workaround in
  [`ci-gitea.yml`](ci-gitea.yml) (`runuser -u ubuntu`). GitHub-hosted runners already run steps as a normal user.
- Gitea's own address is `http://gitea:3000` (that is how job containers reach it). Links in the web UI therefore
  point to `gitea:3000`; open them as `localhost:3000`, or add the line `127.0.0.1 gitea` to your hosts file.
- Watch a job container exist only while its job runs:
  ```bash
  docker ps --filter label=course=devops --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
  ```
- Container registry, secrets, variables and environments: Gitea has its own versions of each (repo **Settings >
  Actions**). The lessons describe the GitHub way.

## Remove it

```bash
bash down.sh
```

Removes the runner, any leftover job containers, Gitea, both volumes and the network. Check nothing is left:

```bash
docker ps -a --filter label=course=devops
docker volume ls --filter label=course=devops -q
```
