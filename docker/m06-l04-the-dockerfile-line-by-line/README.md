# M06-L04 · The Dockerfile, Line by Line
> Video: Module 6, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- How `docker build` really works: the build context, `.dockerignore`, BuildKit, and which instructions add layers (`RUN`, `COPY`, `ADD`) versus which only change the image config (`ENV`, `ARG`, `LABEL`, `EXPOSE`, `USER`, `HEALTHCHECK`, `CMD`, `ENTRYPOINT`).
- How to order a Dockerfile for the build cache: copy dependency files first, code last.
- How to keep junk and secrets out of the image with `.dockerignore`, and why a build `ARG` is not a safe place for a secret.
- Chaining `RUN` steps and cleaning up in the same layer, `ENV` vs `ARG`, `EXPOSE`, `USER`, `HEALTHCHECK`, `LABEL`.
- Shell form vs exec form, who becomes PID 1, and why that decides whether `docker stop` takes 0.3 s or 10 s.
- `CMD` vs `ENTRYPOINT`, a wrapper script that ends in `exec "$@"`, and linting with hadolint.

## Before you start
- Docker Desktop (or Docker Engine) with BuildKit, which is the default in current versions. The video used Docker Desktop 4.79, engine 29.5.3.
- `bash`, `curl`, `git`, and `python3` (optional, only used to create the fake `.venv`).
- You should have done [M06-L02](../m06-l02-images-layers-and-registries/) (layers, cache, digests) and [M06-L03](../m06-l03-running-containers/) (`docker run`, `-p`, `-P`, `--init`).
- Images the lesson pulls (all pinned): `python:3.12.15-slim`, the `docker/dockerfile:1` frontend, `alpine:3.23.6`, `hadolint/hadolint:v2.15.1`.

## Files in this folder
| File | What it is |
|---|---|
| `setup-mess.sh` | Copies the lesson to a lab folder (`~/m06-l04`) and adds the "messy" files from the hook: a FAKE `.env`, a `.venv`, a 58 MB `eval/` dump and a `.git` folder |
| `copilot/` | Course Copilot, a small FastAPI service: `app/main.py`, `data/courses.json`, `requirements.txt` (fastapi 0.154.0, uvicorn 0.54.0), `.gitignore` |
| `copilot/Dockerfile` | The starting point: the 7-line "blog post" Dockerfile (same as `dockerfiles/Dockerfile.v0`) |
| `copilot/docker-entrypoint.sh` | The wrapper script from the ENTRYPOINT part (checks the course index, then `exec "$@"`) |
| `dockerfiles/Dockerfile.v0` | The blog-post Dockerfile (ADD, two apt RUNs, shell-form CMD) |
| `dockerfiles/Dockerfile.1` ... `Dockerfile.9` | Every step of the rewrite, one instruction at a time (`4a` is the "bad apt" version, `sh` the shell-form CMD version) |
| `dockerfiles/Dockerfile.final` | The finished, lint-clean Dockerfile |
| `dockerfiles/dockerignore` | The `.dockerignore` you copy into `copilot/` |
| `dockerfiles/Dockerfile.latest`, `Dockerfile.untagged` | One-line files to show hadolint's DL3007 / DL3006 |
| `argleak/Dockerfile` | Shows that a build `ARG` leaks into `docker history` (uses a FAKE token) |
| `combos/1.Dockerfile` ... `4.Dockerfile` | Four tiny Alpine images: every CMD / ENTRYPOINT combination |

## Follow along

Image tags are `copilot:<step>`; containers are `copilot-<something>`. Every Dockerfile step overwrites `copilot/Dockerfile`, exactly as in the video.

> Docker Desktop note: the video found that Docker Desktop gave containers a stop timeout of 1 second, while Docker's documented default on Linux is 10 seconds. That's why every timed stop below uses `docker stop -t 10`.

### 1. Set up the messy project
```bash
cd Devops_Course/docker/m06-l04-the-dockerfile-line-by-line
bash setup-mess.sh            # creates ~/m06-l04
cd ~/m06-l04/copilot
ls -A
```

### 2. The hook: the blog-post Dockerfile
Build it with plain progress so every step prints:
```bash
time docker build --progress=plain --label course=devops -t copilot:v0 .
```
You should see the whole folder sent to the builder, and a warning about the shell-form CMD:
```
#1 WARN: JSONArgsRecommended: JSON arguments recommended for CMD to prevent unintended behavior related to OS signals (line 7)
#5 transferring context: 86.97MB 0.6s done
```
Now change one string in `app/main.py`: `"...could not find a course for that."` becomes `"...could not find a course for that yet."`. Then build again:
```bash
time docker build --progress=plain --label course=devops -t copilot:v0 .
```
`apt-get update`, `apt-get install curl` and `pip install` all run again (about 8.5 s in the video) for one changed string.

Run it, and stop it:
```bash
docker run -d --name copilot-v0 -p 8000:8000 copilot:v0
curl localhost:8000/health
curl "localhost:8000/ask?q=docker"
time docker stop -t 10 copilot-v0
docker ps -a --filter name=copilot-v0 --format "{{.Names}}  {{.Status}}"
```
You should see:
```
{"status":"ok","version":"dev","courses":5}
{"answer":"Try the DevOps course."}
  0.01s user 0.01s system 0% cpu 10.199 total
copilot-v0  Exited (137) Less than a second ago
```
And look inside the image:
```bash
docker run --rm copilot:v0 ls -A
docker run --rm copilot:v0 cat .env
docker image ls copilot
```
```
.env  .git  .gitignore  .venv  Dockerfile  app  data  eval  requirements.txt
LLM_API_KEY=sk-FAKE-demo-key-0000-not-real
copilot:v0   770d396ca85a        419MB         93.9MB
```

### 3. Line 1 and 2: the syntax directive and FROM
```bash
cp ../dockerfiles/Dockerfile.1 Dockerfile
cat Dockerfile
docker build --progress=plain --label course=devops -t copilot:1 .
docker run --rm copilot:1 python --version
```
The build output proves the directive works: it resolves `docker/dockerfile:1` and uses it by digest (`4edf897a...`, version 1.27.1 on the day of recording). `python --version` prints `Python 3.12.15`.

Optional, to see that the exact tag and `3.12-slim` pointed to the same digest that day:
```bash
docker buildx imagetools inspect python:3.12.15-slim
docker buildx imagetools inspect python:3.12-slim
```

### 4. Order for the cache
```bash
cp ../dockerfiles/Dockerfile.2 Dockerfile
time docker build --progress=plain --label course=devops -t copilot:2 .
```
The first build installs the dependencies (6.4 s in the video). Now make the same kind of one-line change: in `app/main.py`, change the answer to `"...could not find a course for that yet. Try asking about docker!"`. Build again:
```bash
time docker build --progress=plain --label course=devops -t copilot:2 .
```
You should see:
```
#9 [3/5] COPY requirements.txt .
#9 CACHED
#10 [4/5] RUN pip install --no-cache-dir -r requirements.txt
#10 CACHED
#11 [5/5] COPY . .
#11 DONE 0.2s
  0.10s user 0.12s system 8% cpu 2.614 total
```

### 5. The build context still sweeps in everything
```bash
docker run --rm copilot:2 ls -A
docker run --rm copilot:2 du -sh .venv eval .git
docker run --rm copilot:2 cat .env
```
```
31M	.venv
58M	eval
220K	.git
```
The fix is a `.dockerignore` next to the Dockerfile:
```bash
cp ../dockerfiles/dockerignore .dockerignore
cat .dockerignore
docker build --progress=plain --label course=devops -t copilot:3 .
docker run --rm copilot:3 ls -A
docker run --rm copilot:3 cat .env
docker image ls copilot
```
You should see:
```
#5 transferring context: 136B done          <- load .dockerignore
#7 transferring context: 213B 0.0s done     <- load build context
.gitignore  app  data  requirements.txt
cat: .env: No such file or directory
copilot:2    e2a6bec087e0        345MB         66.2MB
copilot:3    86ee3b57a092        239MB         52.3MB
```

### 6. RUN: chain and clean up in one layer
First the blog's way (two separate RUNs):
```bash
cp ../dockerfiles/Dockerfile.4a Dockerfile
docker build -q --label course=devops -t copilot:4a .
docker history --format "table {{.Size}}\t{{.CreatedBy}}" copilot:4a
```
```
18.4MB    RUN /bin/sh -c apt-get install -y curl # bui…
21.3MB    RUN /bin/sh -c apt-get update # buildkit
```
Then one chained RUN that deletes the apt lists in the same step:
```bash
cp ../dockerfiles/Dockerfile.4 Dockerfile
docker build --progress=plain --label course=devops -t copilot:4 .
docker history --format "table {{.Size}}\t{{.CreatedBy}}" copilot:4
docker image ls copilot
```
```
14.5MB    RUN /bin/sh -c apt-get update  && apt-get in…
copilot:4    47bf651fb646        259MB         57.3MB
copilot:4a   00da63942979        301MB         74.4MB
```

### 7. ENV vs ARG
```bash
cp ../dockerfiles/Dockerfile.5 Dockerfile
docker build --progress=plain --label course=devops \
  --build-arg APP_VERSION=1.4.0 -t copilot:5 .
docker run -d --name copilot-v5 -p 8005:8000 copilot:5
curl localhost:8005/health
docker image inspect --format "{{json .Config.Env}}" copilot:5
docker rm -f copilot-v5
```
```
{"status":"ok","version":"1.4.0","courses":5}
[..., "PYTHONUNBUFFERED=1","COURSE_INDEX=/app/data/courses.json","APP_VERSION=1.4.0"]
```
Because the `ARG` sits near the bottom, a new value doesn't break the cache for the expensive steps:
```bash
docker build --progress=plain --label course=devops \
  --build-arg APP_VERSION=1.4.1 -t copilot:5 .
```
Every step says `CACHED`.

### 8. Can an ARG carry a secret? (FAKE token)
```bash
cd ~/m06-l04
docker build -q --label course=devops \
  --build-arg PIP_INDEX_TOKEN=FAKE-demo-token-123 -t argleak:1 argleak
docker image inspect --format "{{json .Config.Env}}" argleak:1
docker history --no-trunc --format "{{.CreatedBy}}" argleak:1 | head -2
cd copilot
```
The environment is clean, but history shows the token twice:
```
RUN |1 PIP_INDEX_TOKEN=FAKE-demo-token-123 /bin/sh -c test -n "$PIP_INDEX_TOKEN" && echo "private package index configured" # buildkit
ARG PIP_INDEX_TOKEN=FAKE-demo-token-123
```
Build secrets (the right tool) come in module 7.

### 9. USER and EXPOSE
```bash
docker run --rm copilot:5 whoami                 # root
cp ../dockerfiles/Dockerfile.6 Dockerfile
docker build -q --label course=devops --build-arg APP_VERSION=1.4.1 -t copilot:6 .
docker run --rm copilot:6 whoami
docker run --rm copilot:6 id
docker run --rm copilot:6 touch app/main.py
```
```
copilot
uid=999(copilot) gid=999(copilot) groups=999(copilot)
touch: cannot touch 'app/main.py': Permission denied
```
`EXPOSE` publishes nothing; it only documents. `-P` reads it:
```bash
docker image inspect --format "{{json .Config.ExposedPorts}}" copilot:6
docker run -d --name copilot-v6 -P copilot:6
docker port copilot-v6
curl localhost:<the port docker port printed>/health
docker rm -f copilot-v6
```
In the video `docker port` printed `8000/tcp -> 0.0.0.0:55001`; your port number will differ.

### 10. HEALTHCHECK
```bash
cp ../dockerfiles/Dockerfile.7 Dockerfile
docker build -q --label course=devops --build-arg APP_VERSION=1.4.1 -t copilot:7 .
docker run -d --name copilot-ok copilot:7
docker run -d --name copilot-sick -e COURSE_INDEX=/app/data/missing.json copilot:7
docker ps --filter name=copilot- --format "table {{.Names}}\t{{.Status}}"
```
Run the `docker ps` line again after ~10 s and after ~25 s:
```
copilot-sick   Up 9 seconds (health: starting)
copilot-ok     Up 9 seconds (healthy)
...
copilot-sick   Up 23 seconds (unhealthy)
copilot-ok     Up 23 seconds (healthy)
```
```bash
docker inspect --format "{{json .State.Health.Status}} {{.State.Health.FailingStreak}}" copilot-sick
docker logs --tail 3 copilot-sick
docker rm -f copilot-ok copilot-sick
```
The log shows `/health` answering `503 Service Unavailable`. The sick container is still `Up`: Docker only reports health.

### 11. LABEL
```bash
cp ../dockerfiles/Dockerfile.8 Dockerfile
docker build -q --label course=devops --build-arg APP_VERSION=1.4.1 -t copilot:8 .
docker image inspect --format "{{json .Config.Labels}}" copilot:8
docker image ls --filter label=org.opencontainers.image.title=course-copilot
```
```
{"course":"devops","org.opencontainers.image.source":"https://github.com/allcsvideos/course-copilot","org.opencontainers.image.title":"course-copilot","org.opencontainers.image.version":"1.4.1"}
```

### 12. Shell form vs exec form: who is PID 1?
Shell-form CMD first:
```bash
cp ../dockerfiles/Dockerfile.sh Dockerfile
docker build -q --label course=devops --build-arg APP_VERSION=1.4.1 -t copilot:sh .
docker run -d --name copilot-sh copilot:sh
docker top copilot-sh -o pid,args
time docker stop -t 10 copilot-sh
docker ps -a --filter name=copilot-sh --format "{{.Names}}  {{.Status}}"
```
```
/bin/sh -c uvicorn app.main:app --host 0.0.0.0 --port 8000
/usr/local/bin/python3.12 /usr/local/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
  0.01s user 0.01s system 0% cpu 10.143 total
copilot-sh  Exited (137) Less than a second ago
```
Exec form (image 8):
```bash
docker run -d --name copilot-exec copilot:8
docker top copilot-exec -o pid,args
time docker stop -t 10 copilot-exec
docker ps -a --filter name=copilot-exec --format "{{.Names}}  {{.Status}}"
docker logs --tail 4 copilot-exec
```
```
  0.01s user 0.01s system 5% cpu 0.310 total
copilot-exec  Exited (0) Less than a second ago
INFO:     Shutting down
INFO:     Waiting for application shutdown.
INFO:     Application shutdown complete.
INFO:     Finished server process [1]
```

### 13. CMD vs ENTRYPOINT: four tiny images
```bash
cd ~/m06-l04
for n in 1 2 3 4; do docker build -q --label course=devops -t combo:$n -f combos/$n.Dockerfile combos; done
docker run --rm combo:1
docker run --rm combo:1 echo hi
docker run --rm combo:2
docker run --rm combo:2 hi
docker run --rm combo:3
docker run --rm combo:3 hi
docker run --rm combo:4
docker run --rm combo:4 hi
docker run --rm --entrypoint echo combo:3 bye
docker image inspect --format "{{json .Config.Entrypoint}} {{json .Config.Cmd}}" combo:4
cd copilot
```
You should see, in order: `hello from CMD`, `hi`, `entry:`, `entry: hi`, `entry: default args`, `entry: hi`, `entry:`, `entry:`, `bye`, and for image 4 `["/bin/sh","-c","echo entry:"] ["default","args"]` (the shell form silently drops CMD and your arguments).

### 14. ENTRYPOINT with a wrapper script
Read `docker-entrypoint.sh`: it checks `$COURSE_INDEX`, logs one line, then `exec "$@"`.
```bash
cat docker-entrypoint.sh
cp ../dockerfiles/Dockerfile.9 Dockerfile
docker build -q --label course=devops --build-arg APP_VERSION=1.4.1 -t copilot:9 .
docker run -d --name copilot -p 8000:8000 copilot:9
docker logs copilot
docker top copilot -o pid,args
curl localhost:8000/health
```
```
entrypoint: Course Copilot 1.4.1, index /app/data/courses.json
INFO:     Started server process [1]
```
Override the CMD, skip the wrapper, and break the config on purpose:
```bash
docker run --rm copilot:9 python --version
docker run --rm --entrypoint python copilot:9 --version
docker run --rm -e COURSE_INDEX=/app/data/missing.json copilot:9; echo "exit code $?"
time docker stop -t 10 copilot
docker rm copilot
```
```
entrypoint: course index /app/data/missing.json not found
exit code 1
  0.01s user 0.00s system 3% cpu 0.393 total
```

### 15. Lint with hadolint
```bash
docker run --rm -i hadolint/hadolint:v2.15.1 < ../dockerfiles/Dockerfile.v0; echo "exit code $?"
docker run --rm -i hadolint/hadolint:v2.15.1 < Dockerfile; echo "exit code $?"
```
The blog version has 8 findings (DL3020 error: use COPY instead of ADD, plus DL3009, DL3008, DL3015, DL3059 x2, DL3042, DL3025). Your step-9 Dockerfile has three left:
```
-:5 DL3008 warning: Pin versions in apt get install. ...
-:19 DL3066 info: Non-numeric user-id may not be resolvable by host system
-:21 DL3025 warning: Use arguments JSON notation for CMD and ENTRYPOINT arguments
exit code 1
```
Read the exact curl version in the image, then switch to the finished Dockerfile (pinned curl, uid/gid 10001, `USER 10001:10001`, and a `# hadolint ignore=DL3025` comment explaining why the HEALTHCHECK keeps its shell form):
```bash
docker run --rm --entrypoint dpkg-query copilot:9 -W curl
cp ../dockerfiles/Dockerfile.final Dockerfile
docker run --rm -i hadolint/hadolint:v2.15.1 < Dockerfile; echo "exit code $?"
```
```
curl	8.14.1-2+deb13u7
exit code 0
```
> If the final build fails with "Version '8.14.1-2+deb13u7' for 'curl' was not found", Debian has since shipped a newer security update. Use the version `dpkg-query` printed for you in `Dockerfile` instead.

The two "never do this" base images:
```bash
docker run --rm -i hadolint/hadolint:v2.15.1 < ../dockerfiles/Dockerfile.latest
docker run --rm -i hadolint/hadolint:v2.15.1 < ../dockerfiles/Dockerfile.untagged
```
`DL3007` (Using latest ...) and `DL3006` (Always tag the version of an image explicitly).

### 16. A clean release build and the finished image
```bash
time docker build --no-cache --progress=plain --label course=devops \
  --build-arg APP_VERSION=1.4.1 -t copilot:1.4.1 .
docker run -d --name copilot -p 8000:8000 copilot:1.4.1
docker ps --filter name=copilot --format "{{.Names}}  {{.Status}}"
docker exec copilot whoami
curl "localhost:8000/ask?q=kubernetes"
docker image ls copilot
time docker stop -t 10 copilot
```
```
copilot  Up 8 seconds (healthy)
copilot
{"answer":"Try the DevOps course."}
copilot:1.4.1   7062de3fd6eb        259MB         57.3MB
copilot:v0      770d396ca85a        419MB         93.9MB
  0.01s user 0.00s system 3% cpu 0.313 total
```
419 MB became 259 MB, the download (content size) went from 93.9 MB to 57.3 MB, and `docker stop` takes 0.3 s instead of 10.

## Common mistakes
1. `apt-get update` in its own `RUN`: that layer is cached with old package lists, and a later install fails or gets stale packages. Update and install in the same `RUN`.
2. `COPY . .` too early: every code change reinstalls every dependency. Copy dependency files first, code last.
3. Secrets in the image: a `.env` swept in by `COPY`, an `ENV` line, or a build `ARG` are all readable. Use `.dockerignore`, pass secrets at run time, and use build secrets.
4. Running as root, the default. Create a user, switch with `USER`, and use a numeric ID.
5. Shell-form `CMD` or `ENTRYPOINT`: the shell is PID 1, SIGTERM never reaches the app, every stop waits for SIGKILL (10 s, exit 137).
6. A `latest` or untagged base image (`python:latest`, bare `python`): your next build silently gets a new base. Pin the exact version.

## Clean up
```bash
docker rm -f copilot copilot-v0 copilot-v5 copilot-v6 copilot-ok copilot-sick copilot-sh copilot-exec 2>/dev/null
docker rmi copilot:v0 copilot:1 copilot:2 copilot:3 copilot:4a copilot:4 copilot:5 copilot:6 copilot:7 \
  copilot:8 copilot:sh copilot:9 copilot:1.4.1 argleak:1 combo:1 combo:2 combo:3 combo:4
rm -rf ~/m06-l04
```
The pulled base and tool images (`python:3.12.15-slim`, `alpine:3.23.6`, `hadolint/hadolint:v2.15.1`) are useful later; remove them with `docker rmi` only if you want the disk space back.

## Next
[M06-L05 · Volumes and Bind Mounts](../m06-l05-volumes-and-bind-mounts/)
