# M07-L02 · Docker Compose
> Video: Module 7, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- Describe a whole local stack (services, networks, volumes, configs, secrets) in one `compose.yaml` and start it with one command.
- Why `depends_on` alone is not enough, and how health checks with `condition: service_healthy` fix the start-up race.
- Keep values out of the file with `.env`, `${VAR:?error}` / `${VAR:-default}`, `env_file`, and read the resolved file with `docker compose config`.
- Use profiles for heavy or debug services, and override files to split dev from prod.
- The everyday commands: `run --rm`, `exec`, `logs`, `stop`/`start`, `down` vs `down -v`, `pull`, `build`, `watch`, `--scale`.
- Where Compose stops: one host, no real load balancing.

## Before you start
- Docker Desktop with the Compose plugin (`docker compose`, with a space). The video used Docker Desktop 4.79, engine 29.5.3, Docker Compose v5.1.4.
- `curl` and a bash/zsh terminal.
- Ideas from M06-L03 (restart policies, loopback ports), M06-L05 (named volumes) and M06-L06 (networks, `internal: true`). The storefront and Copilot Dockerfiles come from [M07-L01](../m07-l01-small-fast-images/).
- Free host ports: 8080 (storefront), 8000 (Copilot), 8081 (Adminer), 55432 (Postgres, dev override only).

The video works in Asha's `allcsvideos` folder with a small **API stand-in** (a Python service that checks Postgres and Redis). The real Spring Boot API arrives in [M07-B01](../m07-b01-containerise-the-allcsvideos-stack/). The project here is named `compose-lab`, so every container, network and volume starts with `compose-lab`.

## Files in this folder
| File | What it is |
|------|------------|
| `stack/api/` | API stand-in: `app.py` (fails fast if the database does not answer), `Dockerfile`, `api.env` (used from step 5) |
| `stack/storefront/` | Vite site served by nginx (M07-L01 Dockerfile) and `default.conf` (proxies `/api/` to `http://api:8080/`) |
| `stack/copilot/` | Course Copilot stand-in, multi-stage Dockerfile with `build`, `test` and `runtime` stages (M07-L01) |
| `stack/db/migrations/001_courses.sql` | One-off migration: creates and seeds the `courses` table (safe to rerun) |
| `stack/.gitignore` | Keeps `.env` and `secrets/` out of Git |
| `stages/s1-compose.yaml` ... `s7-compose.yaml` | `compose.yaml` at each step of the video (s2b and s3b are the small fixes) |
| `stages/compose.override.yaml` | Dev additions, loaded automatically: `LOG_LEVEL=debug`, a `watch` rule, Postgres on 127.0.0.1:55432 |
| `stages/compose.prod.yaml` | Prod-ish settings: `LOG_LEVEL=warning`, `restart: always`, 256M memory limit |
| `stages/env-step5.env`, `env-step7.env` | The `.env` file for step 5 (fake password) and for step 7 (port only) |
| `stages/db_password.txt.example` | The FAKE demo password used as a Compose secret in step 7 |

## Follow along

### 0. Make your working copy
```bash
cp -R stack ~/compose-lab
cd ~/compose-lab
export STAGES="$OLDPWD/stages"     # the stages folder of this lesson
docker compose version
```
You should see `Docker Compose version v5.1.4` (or newer).

### 1. (Optional) The fragile way: commands typed by hand
This is the "setup notes" from the hook. Order matters, and the API loses the race.
```bash
docker build -t compose-lab/api:1.1 api
docker build -t compose-lab/web:2 storefront
docker network create compose-lab-front
docker network create --internal compose-lab-back
docker run -d --name compose-lab-db --network compose-lab-back --network-alias db -e POSTGRES_PASSWORD=demo-password-123 -v compose-lab-pgdata:/var/lib/postgresql postgres:18.6-alpine3.24
docker run -d --name compose-lab-redis --network compose-lab-back --network-alias redis redis:8.10.2-alpine3.23
docker run -d --name compose-lab-api --network compose-lab-back --network-alias api -e DB_HOST=db -e REDIS_HOST=redis compose-lab/api:1.1
docker network connect --alias api compose-lab-front compose-lab-api
docker run -d --name compose-lab-web --network compose-lab-front -p 127.0.0.1:8080:80 -v ./storefront/default.conf:/etc/nginx/conf.d/default.conf:ro compose-lab/web:2
docker ps -a --filter 'name=compose-lab-' --format 'table {{.Names}}\t{{.Status}}'
docker logs compose-lab-api
curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/api/health
```
You may see (it is a race, so your run can differ):
```
compose-lab-api     Exited (1) 19 seconds ago
allcsvideos api 1.1 on 27a79fd653c3: database db:5432 -> ConnectionRefusedError: [Errno 111] Connection refused
cannot reach the database, exiting
502
```
`docker start compose-lab-api` makes it work the second time. Remove all of it before going on:
```bash
docker rm -f compose-lab-web compose-lab-api compose-lab-redis compose-lab-db
docker network rm compose-lab-front compose-lab-back
docker volume rm compose-lab-pgdata
```

### 2. The first compose file (and the same race)
`s2-compose.yaml` has `name`, an `x-labels` anchor reused with `labels: *labels`, services `db` (Postgres with an inline FAKE password and the `pgdata` volume), `redis`, and `api` (`build: ./api`, `DB_HOST: db`, `REDIS_HOST: redis`, `depends_on: [db, redis]`). Read it, then:
```bash
cp "$STAGES/s2-compose.yaml" compose.yaml
docker compose up -d
docker compose ps -a
docker compose logs api
docker compose logs -t --no-log-prefix api
docker compose logs -t db | grep -E 'ready to accept|init process complete|listening on IPv4'
```
You should see the API `Exited (1)` with `Connection refused`. The timestamps show why: Postgres logs "ready to accept connections" first for its temporary setup server (local socket only), and only a moment later `listening on IPv4 address "0.0.0.0", port 5432`. `depends_on` waited for the container to *start*, not for the database to be *ready*.
```bash
docker compose up -d        # second try: Postgres is already running, so the API starts
docker compose logs api
```

### 3. Band-aid: a restart policy
`s2b` adds `restart: on-failure` to the API. `down -v` removes everything, volume included, so you replay a first run.
```bash
cp "$STAGES/s2b-compose.yaml" compose.yaml
docker compose down -v
docker compose up -d
sleep 6; docker compose ps --format "table {{.Service}}\t{{.Status}}"
docker compose logs api
docker inspect -f '{{.RestartCount}}' compose-lab-api-1
```
You should see a couple of refused attempts, then `database db:5432 -> ok`, and a restart count above 0 (the video got `2`). It recovers, but only by crashing first.

### 4. The real fix: health checks
`s3` adds health checks (`pg_isready -h localhost` over TCP for db, `redis-cli ping` for redis, `wget` on `/health` for the API), `depends_on` with `condition: service_healthy`, and `restart: unless-stopped`.
```bash
cp "$STAGES/s3-compose.yaml" compose.yaml
docker compose down -v
docker compose up -d
docker compose ps
docker compose logs api
```
While it starts, db and redis say `Waiting` and the API is only `Created`; then:
```
 ✔ Container compose-lab-redis-1 Healthy        2.7s
 ✔ Container compose-lab-db-1    Healthy        2.7s
 ✔ Container compose-lab-api-1   Started        2.8s
```
The API connects on the first try. But wait about 20 seconds and check again:
```bash
docker compose ps --format "table {{.Service}}\t{{.Status}}"
docker inspect -f '{{range .State.Health.Log}}{{.Output}}{{end}}' compose-lab-api-1
docker compose exec api getent hosts localhost
```
```
api       Up 24 seconds (unhealthy)
wget: can't connect to remote host: Connection refused
::1               localhost  localhost
```
In this Alpine image `localhost` means IPv6 (`::1`) first, and the API listens on IPv4 only. `s3b` uses `127.0.0.1` in the check:
```bash
cp "$STAGES/s3b-compose.yaml" compose.yaml
docker compose up -d
docker compose ps --format "table {{.Service}}\t{{.Status}}"
```
All three should be `(healthy)` after a few seconds. A health check needs testing too.

### 5. Storefront, two networks, loopback port
`s4` adds the `storefront` service (built from `./storefront`), port `127.0.0.1:8080:80`, the nginx config through `configs:`, `depends_on` the healthy API, and two networks: storefront on `front`, db and redis on `back`, the API on both. `back` is `internal: true`.
```bash
cp "$STAGES/s4-compose.yaml" compose.yaml
docker compose down
docker compose up -d
curl -s localhost:8080
curl -s localhost:8080/api/health
docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"
docker network ls --filter name=compose-lab
docker compose exec storefront ping -c1 -W2 db
docker compose exec api ping -c1 -W2 db
```
You should see the storefront HTML, then `{"api": "...", "db": "ok", "redis": "ok"}`, one published port `127.0.0.1:8080->80/tcp`, and from the storefront `ping: bad address 'db'` (the front network has never heard of it), while the API reaches db.

### 6. Values out of the file: .env, env_file, config
`s5` uses `${POSTGRES_PASSWORD:?set it in .env}` (required, with an error message) and `${STOREFRONT_PORT:-8080}` (default 8080), and gives the API `env_file: ./api/api.env` (`LOG_LEVEL`, `COPILOT_URL`).
```bash
cp "$STAGES/s5-compose.yaml" compose.yaml
cp "$STAGES/env-step5.env" .env           # FAKE demo password; .env is git-ignored
docker compose config
```
Look at the API's `environment:` (all four variables, `env_file` merged in), the storefront `published: "8080"`, and the db password in plain text. Hold that thought (step 11).
```bash
mv .env .env.bak
docker compose config --quiet
mv .env.bak .env
docker compose config --quiet && echo valid
STOREFRONT_PORT=8088 docker compose config storefront | grep published
docker compose config storefront | grep published
```
```
error while interpolating services.db.environment.POSTGRES_PASSWORD: required variable POSTGRES_PASSWORD is missing a value: set it in .env
valid
        published: "8088"
        published: "8080"
```
A variable set in the shell wins over `.env`. Now apply it:
```bash
docker compose up -d
docker compose exec api env | grep -E "LOG_LEVEL|COPILOT_URL|DB_HOST"
```

### 7. Profiles: Copilot, a migration job, debug tools
`s6` adds `copilot` (profile `copilot`, long-form `build:` with `target: runtime` and `args: APP_VERSION: "1.5.0"`), `migrate` (profile `tools`, a one-off `psql` job), and `netshoot` + `adminer` (profile `debug`).
```bash
cp "$STAGES/s6-compose.yaml" compose.yaml
docker compose config --services
docker compose --profile debug config --services
docker compose --profile copilot up -d
curl -s localhost:8000/health
docker compose --profile debug up -d
docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"
curl -s localhost:8081 | grep -o '<title>[^<]*'
docker compose exec netshoot dig +short db
docker compose exec netshoot dig +short copilot
```
You should see four services, then six with `--profile debug`; Copilot answers `{"status":"ok","version":"1.5.0","courses":5}` (its `test` stage never runs); seven services in `ps`; Adminer's `<title>Login - Adminer`; and two IP addresses from `dig`.

### 8. Everyday commands
```bash
docker compose run --rm migrate
docker compose exec db psql -U allcsvideos -c "SELECT * FROM courses"
docker compose logs -f --tail 2 api          # in another terminal: curl -s localhost:8080/api/health ; Ctrl-C to stop following
docker compose stop api
docker compose ps -a api --format "table {{.Service}}\t{{.Status}}"
docker compose start api
docker compose ps api --format "table {{.Service}}\t{{.Status}}"
```
`run --rm migrate` waits for db to be healthy, prints `CREATE TABLE` and `INSERT 0 3`, and removes itself (naming the service runs it even with its profile off). The select shows three rows. `stop` gives `Exited (0)`; `start` checks db and redis are healthy first.

Now `down`, and why it leaves things behind:
```bash
docker compose down
docker ps --filter name=compose-lab- --format "table {{.Names}}\t{{.Status}}"
docker compose --profile "*" down
docker volume ls --filter name=compose-lab
```
```
 ! Network compose-lab_back           Resource is still in use
 ! Network compose-lab_front          Resource is still in use
...
local     compose-lab_pgdata
```
Plain `down` only touches services in the active profiles; adminer, netshoot and Copilot keep running. `--profile "*"` removes everything, but the volume survives:
```bash
docker compose up -d
docker compose exec db psql -U allcsvideos -tc "SELECT count(*) FROM courses"     # 3
```
Now on purpose, the dangerous one:
```bash
docker compose down -v
docker compose up -d
docker compose exec db psql -U allcsvideos -tc "SELECT count(*) FROM courses"
```
```
 ✔ Volume compose-lab_pgdata          Removed
ERROR:  relation "courses" does not exist
```
Gone, with no question asked. The migration rebuilds the schema and seed rows; real data only comes back from a backup.
```bash
docker compose run --rm migrate
docker compose pull db redis
docker compose build api
docker compose up -d
```

### 9. Dev vs prod: override files and watch
```bash
cp "$STAGES/compose.override.yaml" .
cp "$STAGES/compose.prod.yaml" .
diff <(docker compose config) <(docker compose -f compose.yaml -f compose.prod.yaml config)
docker compose up -d
```
`compose.override.yaml` is loaded automatically on top of `compose.yaml`. With `-f compose.yaml -f compose.prod.yaml` it is not. The diff shows the prod file losing the `develop.watch` rule and the database port, gaining the memory limit (`"268435456"`), and swapping `LOG_LEVEL` and `restart`.

The watch rule (`action: sync+restart`, `path: ./api/app.py`, `target: /app/app.py`) copies the file in and restarts the container, no rebuild:
```bash
docker compose watch
```
When it says `Watch enabled`, open `api/app.py` in your editor, change `VERSION = "1.1"` to `VERSION = "1.2"` and save. You should see:
```
Syncing service "api" after 1 changes were detected
Container compose-lab-api-1 Restarting
service(s) ["api"] restarted
``` Press Ctrl-C, then:
```bash
docker compose up -d
curl -s localhost:8080/api/whoami          # "version": "1.2"
```
The other actions are `rebuild` (for example a new dependency) and `sync` alone (apps that reload by themselves).

### 10. Scaling is not load balancing
```bash
docker compose up -d --scale api=2
docker compose ps api --format "table {{.Name}}\t{{.Status}}"
docker compose run --rm netshoot dig +short api
for i in 1 2 3 4 5 6; do curl -s localhost:8080/api/whoami; done
docker compose restart storefront
for i in 1 2 3 4 5 6; do curl -s localhost:8080/api/whoami; done
docker compose run --rm netshoot sh -c "for i in 1 2 3 4 5 6; do curl -s api:8080/whoami; done"
docker compose up -d --scale api=1
```
`dig` returns two addresses for `api`. Through the storefront every request hits the same container (nginx resolved `api` once at start-up); after a restart it sticks to the other one. From netshoot, new connections spread roughly (the video got 5:1). Look at the version too: `1.1`. Scaling recreated the API from its image, and `watch` had only changed the old container. Rebuild (`docker compose build api`) before you scale or recreate.

### 11. Pitfalls, live
**The `version` key.** Paste an old header into a copy and validate it:
```bash
{ echo 'version: "3.8"'; cat compose.yaml; } > /tmp/compose-version.yaml
docker compose -f /tmp/compose-version.yaml config --quiet
rm /tmp/compose-version.yaml
```
```
WARN[0000] ... the attribute `version` is obsolete, it will be ignored, please remove it to avoid potential confusion
```
**Port clashes.** Another container takes 127.0.0.1:8081 first:
```bash
docker run -d --rm --name squatter -p 127.0.0.1:8081:80 nginx:1.29.8-alpine
docker ps --filter publish=8081 --format "table {{.Names}}\t{{.Ports}}"
docker compose --profile debug up -d adminer       # Bind for 127.0.0.1:8081 failed: port is already allocated
docker rm -f squatter
docker compose --profile debug rm -f adminer
```
**latest tags.** The two built images are tagged `latest` by default:
```bash
docker compose images
```
**Secrets in compose files.** `s7` moves the password into a Compose secret: db reads `POSTGRES_PASSWORD_FILE: /run/secrets/db_password`, the file comes from `secrets/db_password.txt` (git-ignored with `.env`), and `.env` keeps only `STOREFRONT_PORT`.
```bash
cp "$STAGES/s7-compose.yaml" compose.yaml
cp "$STAGES/env-step7.env" .env
mkdir -p secrets
cp "$STAGES/db_password.txt.example" secrets/db_password.txt     # FAKE demo value
docker compose config db | grep -iE -A2 "password|secrets"
docker compose up -d
docker compose exec db ls -l /run/secrets
cat .gitignore
docker compose run --rm migrate
curl -s localhost:8080/api/health
```
`config` now shows only the file's path (`POSTGRES_PASSWORD_FILE: /run/secrets/db_password`), the secret appears as a file inside db, and the migration runs again with `INSERT 0 0` because it is safe to rerun. On one host a Compose secret is just a mounted file; Module 18 brings Vault.

## Common mistakes
- **`depends_on` without health checks.** Start order is not readiness. Add a health check and `condition: service_healthy`, and test the check itself (the `localhost` vs `127.0.0.1` slip above was real).
- **`down -v`.** It deletes named volumes, database included, without asking. Use plain `down` every day and keep backups.
- **Secrets in compose files.** `docker compose config` prints environment values in plain text, and a committed `.env` stays in Git history. Use a secret file, git-ignored.
- **`latest` tags.** Pin every image you pull, and give images you build and ship a real tag (M07-L04).
- **Port clashes.** "port is already allocated" means something else holds the host port. Check `docker ps` and keep host ports in `.env`.
- **The `version:` key.** Obsolete; Compose ignores it and warns. Delete it.
- **Forgetting profiles on `down`.** Plain `down` leaves profile services and their networks; use `--profile "*" down`.
- **Scaling after `watch`.** New containers start from the old image. Rebuild first.

## Clean up
```bash
cd ~/compose-lab
docker compose --profile "*" down -v --rmi local     # containers, networks, the pgdata volume, and the images Compose built
docker rmi compose-lab/api:1.1 compose-lab/web:2 2>/dev/null   # only if you did step 1
cd ~ && rm -rf ~/compose-lab
```
The pinned base images (postgres, redis, adminer, netshoot, nginx, node, python) stay in your cache; remove them with `docker rmi` if you want the space back.

## Next
[M07-L03 · Image Security](../m07-l03-image-security/)
