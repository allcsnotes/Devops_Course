# M06-L03 · Running Containers
> Video: Module 6, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- The shape of `docker run` and the flags that matter: `-d`, `-it`, `--rm`, `--name`
- The container lifecycle (created, running, paused, exited, removed) and what exit codes mean (0, 1, 128 + signal)
- Publishing ports with `-p`, why the default `0.0.0.0` is risky, and binding to `127.0.0.1`; `EXPOSE` vs `-P`
- Configuration with `-e` and `--env-file`, precedence, and why env vars leak secrets
- Logs (`docker logs`, the json-file driver, log rotation), looking inside (`exec`, `cp`, `inspect`, `stats`, `top`)
- Clean shutdown (SIGTERM, grace period, PID 1, `--init`) and restart policies

## Before you start
- Docker Desktop (the video used 4.79, engine 29.5.3) or Docker Engine on Linux, and `curl` (on Windows PowerShell type `curl.exe`; a Git Bash or WSL shell is easiest for this lesson).
- Images used, all pinned: `python:3.13.16-alpine3.23` (API base), `nginx:1.29.8-alpine`, `alpine:3.23.6`, `curlimages/curl:8.11.1`.
- Helpful background: [M06-L01](../m06-l01-vms-vs-containers/) (the privileged "lab trick"), [M06-L02](../m06-l02-images-layers-and-registries/) (images and tags), M02-L03 (signals, PID 1, systemd restarts), M04-L03 (NAT and ufw).
- Free host ports: 8080-8085 and 8090.

In the video the image is `do-m06l03/api:1.0` and containers are `do-m06l03-web`, `do-m06l03-api`, ... Here the image is `allcsvideos/api:1.0` and containers drop the prefix (`web`, `api`, ...). The label `lesson=m06l03` is kept for safe cleanup.

## Files in this folder
| File | What it is |
|---|---|
| `api/app.py` | The API stand-in: a small real Python HTTP service (standard library only). Reads `PORT`, `LOG_LEVEL`, `DB_URL`; serves `/health` and `/courses`; logs INFO/DEBUG to stdout and WARNING/ERROR to stderr; handles SIGTERM gracefully. `--no-sigterm-handler` is a staged variant without the handler |
| `api/Dockerfile` | Six lines: pinned Python base, `WORKDIR`, `COPY app.py`, `ENV PORT=8080 LOG_LEVEL=INFO`, `EXPOSE 8080`, `CMD` |
| `api.env` | Env file with **FAKE** demo values (`LOG_LEVEL=DEBUG`, a fake `DB_URL` with a fake password) |
| `index.html` | A one-line maintenance page, copied into nginx with `docker cp` |

## Follow along
Run everything from this folder.

### 1. The hook: who answered on port 8080?
Stage an "old test container" holding port 8080, then build the API image:
```bash
docker run -d --name web --label course=devops --label lesson=m06l03 -p 8080:80 nginx:1.29.8-alpine
cd api
docker build -q --label course=devops --label lesson=m06l03 -t allcsvideos/api:1.0 .
docker image ls allcsvideos/api
cd ..
```
The image uses about 82.9 MB on disk. Now Asha's first try:
```bash
docker run -d --name api allcsvideos/api:1.0
curl localhost:8080/health
```
A `404 Not Found` page signed `nginx/1.29.8`: the API published nothing, so nginx answered. Try again with a port:
```bash
docker rm -f api
docker run -d --name api -p 8080:8080 allcsvideos/api:1.0
docker ps -a --filter label=lesson=m06l03
```
```
Bind for 0.0.0.0:8080 failed: port is already allocated
...
STATUS          PORTS                                     NAMES
Created                                                   api
Up 49 seconds   0.0.0.0:8080->80/tcp, [::]:8080->80/tcp   web
```
The failed run left a container stuck in `Created`. Remove it: `docker rm api`.

### 2. Foreground, detached, interactive
```bash
docker run --rm --name fg allcsvideos/api:1.0
```
Logs stream to your terminal. Press **Ctrl-C**: `SIGINT received: finishing in-flight requests`, `shutdown complete, bye`. With `--rm` it is gone:
```bash
docker ps -a --filter name=fg
```
Detached, with and without a name:
```bash
docker run -d allcsvideos/api:1.0
docker run -d --name bg allcsvideos/api:1.0
docker ps --filter ancestor=allcsvideos/api:1.0
docker logs bg
```
The unnamed one gets a random name (`reverent_banach` in the video). PORTS says `8080/tcp` with no arrow: declared, not published.

Interactive throwaway shell:
```bash
docker run -it --rm --name shell --label course=devops alpine:3.23.6 sh
```
Inside: `hostname` (the short container ID), `ps` (sh is PID 1), then `exit`. The container ends with sh and `--rm` deletes it.

### 3. The lifecycle
```bash
docker create --name life allcsvideos/api:1.0
docker ps -a --filter name=life --format 'table {{.Names}}\t{{.Status}}'
docker start life
docker ps -a --filter name=life --format 'table {{.Names}}\t{{.Status}}'
docker pause life
docker ps -a --filter name=life --format 'table {{.Names}}\t{{.Status}}'
docker unpause life
docker stop life
docker ps -a --filter name=life --format 'table {{.Names}}\t{{.Status}}'
docker rm life
```
Status goes `Created` -> `Up 1 second` -> `Up 4 seconds (Paused)` -> `Exited (0)` -> gone.

### 4. Ports
Pick a free host port for container port 8080:
```bash
docker run -d --name api -p 8081:8080 allcsvideos/api:1.0
curl localhost:8081/health
docker port api
docker inspect --format "{{.NetworkSettings.Networks.bridge.IPAddress}}" api
```
```
{"status": "ok", "version": "1.0"}
8080/tcp -> 0.0.0.0:8081
8080/tcp -> [::]:8081
172.17.0.5
```
`0.0.0.0` means every interface of the host. Bind to loopback instead:
```bash
docker run -d --name local -p 127.0.0.1:8082:8080 allcsvideos/api:1.0
docker port local
curl localhost:8082/health
```
Now play "another machine". On Docker Desktop, the Docker host is a Linux VM; find its address, then curl from a throwaway container:
```bash
docker run --rm --label course=devops --network host alpine:3.23.6 ip -4 addr show eth0
docker run --rm --label course=devops curlimages/curl:8.11.1 -s 192.168.65.3:8081/health
docker run --rm --label course=devops curlimages/curl:8.11.1 -sS 192.168.65.3:8082/health
```
Use the address the first command prints (it was `192.168.65.3` in the video; on Linux, use your host's LAN IP). Port 8081 answers; 8082 says `Could not connect to server`.

`EXPOSE` publishes nothing, but capital `-P` uses it:
```bash
docker image inspect --format '{{json .Config.ExposedPorts}}' allcsvideos/api:1.0
docker run -d --name rand -P allcsvideos/api:1.0
docker port rand
curl localhost:55000/health      # use the port docker port printed
```

### 5. Configuration through the environment
```bash
docker run -d --name env -p 8084:8080 -e LOG_LEVEL=DEBUG -e DB_URL=postgres://api:FAKE-demo-pass-123@db.example.internal:5432/allcs allcsvideos/api:1.0
curl localhost:8084/health
docker logs env
```
`log_level=DEBUG`, the password masked by the app (`api:****@`), and DEBUG lines like `request from 172.17.0.1`.

With a file, plus an override:
```bash
cat api.env
docker run -d --name envf --env-file api.env -e PORT=9000 -p 8085:9000 allcsvideos/api:1.0
curl localhost:8085/courses
docker logs envf
```
The app listens on 9000 (`EXPOSE` still says 8080, and nothing breaks). Precedence:
```bash
docker run --rm --env-file api.env -e LOG_LEVEL=WARNING allcsvideos/api:1.0 printenv PORT LOG_LEVEL
```
```
8080
WARNING
```
Image `ENV`, then `--env-file`, then `-e` (wins). The catch:
```bash
docker inspect --format '{{json .Config.Env}}' env
docker exec env printenv DB_URL
```
The fake password, in plain text, for anyone who can run docker commands on the host.

### 6. Logs
```bash
curl -s localhost:8084/courses > /dev/null
curl -s localhost:8084/admin
docker logs env
docker logs env 2>/dev/null | tail -n 4
```
The 404 is a `WARNING` on stderr, so it disappears when stderr goes to `/dev/null`. Wait about 40 seconds, then:
```bash
curl -s localhost:8084/health > /dev/null
docker logs --tail 3 env
docker logs -t --since 30s env
```
Follow the log, and send requests from a **second terminal** (`curl localhost:8084/courses`, `curl localhost:8084/health`):
```bash
docker logs -f --tail 2 env
```
Ctrl-C stops following, not the container.

Where the logs live:
```bash
docker info --format '{{.LoggingDriver}}'
docker inspect --format '{{json .HostConfig.LogConfig}}' env
docker inspect --format '{{.LogPath}}' env
ID=$(docker inspect --format '{{.Id}}' env)
docker run --rm --label course=devops --privileged --pid=host alpine:3.23.6 nsenter -t 1 -m tail -n 2 /var/lib/docker/containers/$ID/$ID-json.log
```
`json-file`, `{"Type":"json-file","Config":{}}` (no options), and each line is a JSON object with `log`, `stream` and `time`. (The last command is the lab trick from M06-L01 to read the file inside the Docker Desktop VM; on Linux use `sudo tail` on the path directly.)

**No rotation by default**, staged on purpose. This writes about 1.5 GB in 12 seconds, so remove both containers right after:
```bash
docker run -d --name chatty --label course=devops --label lesson=m06l03 alpine:3.23.6 sh -c 'while true; do echo "INFO GET /health 200 - one chatty log line"; done'
docker run -d --name rotated --label course=devops --label lesson=m06l03 --log-opt max-size=1m --log-opt max-file=3 alpine:3.23.6 sh -c 'while true; do echo "INFO GET /health 200 - one chatty log line"; done'
sleep 12
docker stop -t 1 chatty rotated
A=$(docker inspect --format '{{.Id}}' chatty); B=$(docker inspect --format '{{.Id}}' rotated)
docker run --rm --label course=devops --privileged --pid=host alpine:3.23.6 nsenter -t 1 -m du -h /var/lib/docker/containers/$A/$A-json.log
docker run --rm --label course=devops --privileged --pid=host alpine:3.23.6 nsenter -t 1 -m ls -lh /var/lib/docker/containers/$B/ | grep json
docker inspect --format '{{json .HostConfig.LogConfig}}' rotated
docker rm chatty rotated
```
`chatty`: `1.5G`. `rotated`: a live file plus `.1` and `.2`, each under 1 MB. For the whole host, set it in `daemon.json`, for example `"log-opts": {"max-size": "10m", "max-file": "3"}`, or use the `local` driver, which rotates by default.

### 7. Look inside
```bash
docker exec -it env sh
```
Inside: `ps` (`python app.py` is PID 1, your shell is just another process), `printenv LOG_LEVEL PORT`, `wget -qO- 127.0.0.1:8080/health`, `ls`, `exit`. The container keeps running:
```bash
docker ps --filter name=^env$ --format "{{.Names}}  {{.Status}}"
docker exec env python --version
docker exec env cat /etc/alpine-release
docker exec env whoami
```
`Python 3.13.16`, `3.23.6`, `root` (module 7 fixes that).

Copy files out and in:
```bash
docker cp env:/app/app.py ./app-from-container.py
docker cp index.html web:/usr/share/nginx/html/index.html
curl localhost:8080
```
```
<h1>allcsvideos is under maintenance</h1>
```
Inspect, stats, top:
```bash
docker inspect --format '{{.State.Status}} pid={{.State.Pid}} restarts={{.RestartCount}}' env
docker inspect --format '{{.Config.Image}} {{.Path}} {{.Args}}' env
docker inspect --format '{{json .NetworkSettings.Ports}}' env
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.PIDs}}' env web
docker top env
```
The PID from `inspect` matches the one in `docker top`. The memory limit shown by `stats` is the whole VM: no limits are set.

### 8. Stopping, signals and PID 1
The well-behaved API:
```bash
time docker stop env
docker logs --tail 2 env
docker ps -a --filter name=^env$ --format "{{.Names}}  {{.Status}}"
```
About 0.36 s, `SIGTERM received ...`, `shutdown complete, bye`, `Exited (0)`.

Check the grace period on your machine:
```bash
docker run -d --name quick allcsvideos/api:1.0
docker inspect --format '{{.Config.StopTimeout}}' quick
```
The video showed `1`: Docker Desktop gives the containers it creates a one-second grace period. Docker Engine on Linux waits 10 seconds by default.

The staged problem, an app without a SIGTERM handler running as PID 1:
```bash
docker run -d --name stubborn --stop-timeout 10 allcsvideos/api:1.0 python app.py --no-sigterm-handler
docker logs stubborn
docker exec stubborn ps
time docker stop stubborn
docker ps -a --filter name=stubborn --format "{{.Names}}  {{.Status}}"
docker inspect --format 'exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' stubborn
```
About 10.1 s, then `Exited (137)`, `oom=false`: PID 1 ignored SIGTERM, so Docker sent SIGKILL after the grace period.

The fix, `--init`:
```bash
docker run -d --name with-init --init --stop-timeout 10 allcsvideos/api:1.0 python app.py --no-sigterm-handler
docker exec with-init ps
time docker stop with-init
docker ps -a --filter name=with-init --format "{{.Names}}  {{.Status}}"
```
`/sbin/docker-init` is PID 1 and python is PID 7; stop takes about 0.1 s and ends with `Exited (143)` (128 + 15).

Two more endings:
```bash
docker kill quick
docker run --name badport -e PORT=eighty allcsvideos/api:1.0
docker ps -a --filter label=lesson=m06l03 --format "table {{.Names}}\t{{.Status}}"
```
`ERROR   PORT must be a number, got 'eighty'`, and the list shows Exited 1, 143, 137, 137 and 0 side by side.

Clean up so far:
```bash
docker rm badport
docker rm web              # refused: the container is running
docker rm -f web
docker stop $(docker ps -q --filter label=lesson=m06l03)
docker container prune --filter label=lesson=m06l03 --force
docker ps -a --filter label=lesson=m06l03
```
Even the randomly named container is removed: it inherited the `lesson=m06l03` label from the image.

### 9. Restart policies
A crash loop, staged on purpose:
```bash
docker run -d --name crashy --label course=devops --label lesson=m06l03 --restart always alpine:3.23.6 sh -c 'echo "worker starting"; sleep 2; echo "worker: cannot reach the queue, exiting" >&2; exit 1'
for i in 1 2 3 4 5 6 7 8; do echo "t=$((i*5))s $(docker inspect --format '{{.RestartCount}} restarts, {{.State.Status}}' crashy)"; sleep 5; done
docker ps --filter name=crashy --format "{{.Names}}  {{.Status}}"
docker logs --tail 4 crashy
docker inspect --format '{{json .HostConfig.RestartPolicy}} count={{.RestartCount}}' crashy
```
The count climbs, then slows (backoff: 100 ms, 200, 400, 800 ... up to 1 minute, reset after 10 s up). `docker ps` may say `Up Less than a second`, which looks healthy, or `Restarting (1)`.

A manual stop beats `always`:
```bash
docker stop crashy
docker ps -a --filter name=crashy --format "{{.Names}}  {{.Status}}"
```
Run the `ps` again 15 seconds later: still `Exited (1)`.

With a limit:
```bash
docker run -d --name crashy3 --label course=devops --label lesson=m06l03 --restart on-failure:3 alpine:3.23.6 sh -c 'echo "worker starting"; sleep 2; echo "worker: cannot reach the queue, exiting" >&2; exit 1'
sleep 30
docker inspect --format '{{.RestartCount}} restarts, {{.State.Status}}, exit {{.State.ExitCode}}' crashy3
```
```
3 restarts, exited, exit 1
```

### 10. All together
```bash
docker run -d --name prod --init -p 127.0.0.1:8090:8080 --env-file api.env --log-opt max-size=10m --log-opt max-file=3 --restart unless-stopped allcsvideos/api:1.0
curl localhost:8090/health
docker ps --filter name=prod --format "{{.Names}}  {{.Status}}  {{.Ports}}"
docker inspect --format '{{json .HostConfig.RestartPolicy}} {{json .HostConfig.LogConfig.Config}}' prod
docker logs prod
```
```
prod  Up 3 seconds  127.0.0.1:8090->8080/tcp
{"Name":"unless-stopped","MaximumRetryCount":0} {"max-file":"3","max-size":"10m"}
INFO    allcsvideos api 1.0 starting, pid 7
```

## Common mistakes
1. **Publishing on every interface by accident.** `-p 8080:80` means `0.0.0.0`, reachable by anyone who can reach the host, and on Linux it bypasses ufw. Bind to `127.0.0.1` unless the port is meant to be public.
2. **Secrets in environment variables.** `docker inspect` showed the fake password to anyone with Docker access. Use secret files or a secret manager (module 18).
3. **Unbounded logs.** json-file never rotates by default: 1.5 GB in 12 seconds. Set `max-size` and `max-file` per container or in `daemon.json`.
4. **An app that ignores SIGTERM.** Every stop waits the full grace period and ends in SIGKILL (137), cutting off requests. Handle SIGTERM and add `--init`.
5. **`--restart always` hiding crashes.** The worker looked `Up` while crashing every few seconds. Watch `RestartCount`, alert on it, and give jobs `on-failure` with a limit.
6. **Running `latest`.** `docker run nginx` means `nginx:latest`, a moving tag. Pin an exact version like `nginx:1.29.8-alpine`.

## Clean up
```bash
docker rm -f prod crashy crashy3
docker container prune --filter label=lesson=m06l03 --force
docker rmi allcsvideos/api:1.0
rm -f app-from-container.py
```

## Next
[M06-L04 · The Dockerfile, Line by Line](../m06-l04-the-dockerfile-line-by-line/)
