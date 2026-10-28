# M07-B01 · Containerise the allcsvideos Stack
> Video: Module 7, Build 1. Watch it first, then follow along here.

This build created the **allcsvideos platform repo**. It already lives in this course repo at
[`../../allcsvideos`](../../allcsvideos/) (with its own [README](../../allcsvideos/README.md)), so this folder does not
copy it. Here you get the walk-through: how the stack was containerised, why each decision was made, and the exact
commands from the video, run against your own copy of that folder.

## What you'll learn
- How to put real services (web, API gateway, catalog, Course Copilot, PostgreSQL, Redis) behind **one** `docker compose up`, with a health-gated start order and a one-off `migrate` job.
- How the Module 7 pieces fit together: small multi-stage images, hardening (non-root, read-only, no capabilities, health checks), Compose secrets, profiles, a Trivy release gate, SBOMs and semver + commit tags.
- How to make "one command for everything" real with a Makefile, and prove it with a fresh clone (1 min 47 s from clone to healthy in the video).
- How to break the stack on purpose and read what happens: a killed database, a real crash, a bad release, and deleted data.
- What changes at real scale (Kubernetes, CI, a secrets manager, a managed database).

## Before you start
- Docker Desktop (or Docker Engine) with **Compose v2.20 or newer**. The video used Docker Desktop 4.79, engine 29.5.3, Compose v5.1.4.
- `make`, `git`, `curl` and `jq`. On Windows use WSL (recommended) or Git Bash.
- About 3 GB of free disk space and a network connection (Maven, npm and pip download dependencies on the first build).
- Earlier lessons this build puts together: [M06-L06 Container Networking](../m06-l06-container-networking/) (two networks),
  [M07-L01 Small, Fast Images](../m07-l01-small-fast-images/), [M07-L02 Docker Compose](../m07-l02-docker-compose/),
  [M07-L03 Image Security](../m07-l03-image-security/) and [M07-L04 Registries and Tagging](../m07-l04-registries-and-tagging/).
- Port `127.0.0.1:8080` (storefront) and `127.0.0.1:5001` (local registry) must be free.

Pinned images used by the stack: `postgres:18.6-alpine3.24`, `redis:8.10.2-alpine3.23`, `flyway/flyway:12.4.0-alpine`,
`maven:3.9.16-eclipse-temurin-25`, `gcr.io/distroless/java25-debian13:nonroot@sha256:a26596c2…`, `python:3.12.15-slim`,
`node:22.23.3-slim`, `nginxinc/nginx-unprivileged:1.29.8-alpine`, `registry:3.1.2`, `aquasec/trivy:0.76.0@sha256:2416d1f7…`,
`anchore/syft:v1.54.1@sha256:3eb5379b…`, `nicolaka/netshoot:v0.16`, `adminer:6.1.2`.

## Files in this folder

| File | What it is |
|------|------------|
| `README.md` | This walk-through. All the code is in [`../../allcsvideos`](../../allcsvideos/). |

The files of `../../allcsvideos` that this build is about:

| Path in `allcsvideos/` | What it is |
|------|------------|
| `compose.yaml` | The whole stack: 6 core services, 2 networks, 1 volume, 1 secret, profiles `copilot` and `debug`. |
| `Makefile` | `make help / up / down / ps / logs / scan / registry / release / nuke`. |
| `.env.example` | Copied to `.env` by `make up`; `COMPOSE_PROFILES=copilot` turns Course Copilot on. |
| `api/Dockerfile` | One Dockerfile for both Java services (`--build-arg SERVICE=gateway` or `catalog-service`). |
| `api/probe/Probe.java` | A tiny health-check program for distroless images (no shell, no curl). |
| `api/catalog-service/.../CourseCatalog.java`, `CacheConfig.java` | The only code change: Redis cache for the course list, and "Redis down = read the database". |
| `api/catalog-service/src/main/resources/db/migration/` | Flyway migrations `V1__catalog.sql` and `V2__more_courses.sql` (used by the `migrate` job). |
| `copilot/Dockerfile` | Course Copilot, three stages (from M07-L01), runs as uid 10001. |
| `storefront/Dockerfile`, `storefront/nginx/default.conf` | Vite site on unprivileged nginx; proxies `/api/` and `/copilot/`. |
| `scripts/dev-secrets.sh` | Creates a random local DB password once, in the git-ignored `secrets/` folder. |
| `scripts/scan.sh` | The release gate: Trivy, `CRITICAL`, `--ignore-unfixed`, one PASS/FAIL line per image. |
| `scripts/release.sh` | Build once, gate, SBOMs, tag `sha-<commit>` + semver ladder, push, record digests. |

Everything in the stack is named with the prefix `do-m07b01` (Compose project name, images, cache ids, volumes), so
containers are called `do-m07b01-db-1`, `do-m07b01-catalog-1`, and so on.

## The design (what the video explains first)

```
browser ── 127.0.0.1:8080 ──> storefront (nginx, uid 101)
                                 │ /api/*            │ /copilot/*
                                 v                   v
              front network:  gateway ───────────  copilot (profile "copilot")
                                 │  (on both networks)
              back network (internal: true, no route out)
                                 v
                              catalog ──> redis (cache, 60 s)
                                 │
                                 v
                                db (PostgreSQL, volume pgdata) <── migrate (Flyway, runs once, exits 0)
```

- **One published port**, on loopback only: `127.0.0.1:8080`, the storefront.
- **Two networks** (as in M06-L06): `front` holds storefront, gateway and Copilot; `back` is `internal: true` and holds catalog, db and redis. Only the gateway is on both.
- **Health-gated start**: db healthy -> migrate completed successfully -> catalog healthy (and redis healthy) -> gateway healthy -> storefront.
- **Profiles**: Copilot is in `copilot` (switched on in `.env`); netshoot and adminer are in `debug`.
- **Not here yet, on purpose**: the enrollment and payment services talk through a Kafka saga, so they come later. Catalog runs with its Kafka listener and topic creation switched off (the same settings its integration test uses). Course Copilot answers from a keyword index; there is no AI model in this stack.

## Follow along

### Get your own copy (Asha's repo)

The release script tags images with the git commit and needs a remote called `origin`, so make the copy a git repo
and give it a local "team git server" (a bare repo on your disk), like the video did. From this folder:

```bash
cp -R ../../allcsvideos ~/allcsvideos-lab
cd ~/allcsvideos-lab
git init -q -b main && git add . && git commit -qm "allcsvideos platform"
git init -q --bare ~/allcsvideos-git/allcsvideos-platform.git
git remote add origin ~/allcsvideos-git/allcsvideos-platform.git
git push -q -u origin main
```

### Step 1 - The Java images

1. Read `api/Dockerfile`. What to notice:
   - One Dockerfile, a build arg `SERVICE` (`gateway` or `catalog-service`). Every base image is pinned.
   - Build stage: `dependency:go-offline` into a `--mount=type=cache` for `~/.m2`, then `package`, then
     `java -Djarmode=tools ... extract --layers` (the layered jar from M07-L01).
   - Runtime stage: distroless Java 25, pinned by digest: no shell, no package manager, user `nonroot`.
   - A training run records an AOT cache (`-XX:AOTCacheOutput=app.aot`), so the service starts faster.
   - No curl in distroless, so `HEALTHCHECK` runs `Probe`: it calls `/actuator/health` and exits 0 on a 200, else 1, every 10 s.

2. The one code change, in `api/catalog-service/src/main/java/com/allcs/catalog/`:
   - `CourseCatalog.java`: the course list gets `@Cacheable("courses")`. Spring checks Redis first, PostgreSQL only on a miss
     (time to live 60 s, set in `application.yml`).
   - `CacheConfig.java`: a `CacheErrorHandler`. If Redis is down, log a warning and read the database. Redis is a cache, not a dependency.

### Step 2 - Copilot and the storefront

3. `copilot/Dockerfile` keeps its three-stage shape from M07-L01 and runs as user `10001`.

4. `storefront/nginx/default.conf`:

   ```nginx
   listen 8080;                       # unprivileged nginx: no root, no port 80
   resolver 127.0.0.11 valid=10s ipv6=off;
   set $gateway http://gateway:8080;
   set $copilot http://copilot:8000;
   ```

   Docker's DNS is at `127.0.0.11`, and names inside variables are looked up per request. M07-L02 showed nginx keeping
   one address forever; now a recreated gateway is found again, and nginx starts even when Copilot is not running.
   The page itself (`storefront/src/main.js`) fetches `/api/courses`; if that fails it shows the error message and the page stays up.

5. Build all four images and check them:

   ```bash
   time docker compose --profile copilot build
   docker image ls 'do-m07b01/*'
   docker image inspect do-m07b01/catalog:dev --format '{{.Config.User}}'
   docker run --rm --entrypoint sh do-m07b01/catalog:dev
   ```

   ```
   IMAGE                      ID             DISK USAGE   CONTENT SIZE
   do-m07b01/catalog:dev      21cadee6b7b8        554MB          155MB
   do-m07b01/copilot:dev      74410c7c770e        244MB         52.8MB
   do-m07b01/gateway:dev      c9424d546f69        582MB          164MB
   do-m07b01/storefront:dev   f86162fbaa1e       81.6MB         23.1MB
   nonroot
   docker: Error response from daemon: ... exec: "sh": executable file not found in $PATH
   ```

   The first build downloads all dependencies and takes a few minutes; the video's capture shows a warm cache (4.7 s).

### Step 3 - The data layer

6. The DB password is a Compose **secret**, never an environment variable:

   ```bash
   scripts/dev-secrets.sh
   ls secrets/
   git status --short --ignored
   ```

   ```
   created secrets/db_password.txt (random, local only)
   db_password.txt
   !! secrets/
   ```

7. Read the `db`, `redis` and `migrate` services in `compose.yaml`:
   - `db`: Postgres 18.6 on Alpine as user `70`, password from `/run/secrets/db_password`, a tmpfs for the socket folder, the `pgdata` volume.
   - `redis`: cache only: `--save ""`, `--appendonly no`, `--maxmemory 64mb`, `--maxmemory-policy allkeys-lru`, user `999`.
   - `migrate`: `flyway/flyway:12.4.0-alpine` (the same Flyway version catalog uses inside), mounts catalog's migration folder read-only, reads the password from the secret.

8. Start the data layer and run the migration (twice):

   ```bash
   docker compose up -d --wait db redis
   docker compose run --rm migrate
   docker compose run --rm migrate | tail -2
   ```

   ```
   ✔ Container do-m07b01-redis-1 Healthy     2.5s
   ✔ Container do-m07b01-db-1    Healthy     5.0s
   ...
   Successfully validated 2 migrations
   Migrating schema "public" to version "1 - catalog"
   Migrating schema "public" to version "2 - more courses"
   ...
   Schema "public" is up to date. No migration necessary.
   ```

   Safe to run on every start.

9. Check the hardening is real:

   ```bash
   docker compose exec db id
   docker compose exec db touch /etc/hello
   docker compose exec db ls /run/secrets
   ```

   ```
   uid=70(postgres) gid=70(postgres) groups=70(postgres)
   touch: /etc/hello: Read-only file system
   db_password
   ```

### Step 4 - The app services

10. Read the rest of `compose.yaml`:
    - `x-hardened: &hardened` is an extension field with an anchor: `read_only`, `tmpfs: [/tmp]`, `cap_drop: [ALL]`,
      `no-new-privileges`, `restart: unless-stopped`. Every long-running service merges it in with `<<: *hardened`.
    - `catalog` gets `DB_HOST: db`, `REDIS_HOST: redis` and `SPRING_CONFIG_IMPORT: optional:configtree:/run/secrets/`.
      The secret is mounted with `target: spring.datasource.password`: Spring turns the file name into the property, so
      the password never appears in the environment.
    - `SPRING_FLYWAY_ENABLED: "false"` (migrate owns the schema), and the Kafka listener and topic creation are off.
    - `depends_on`: catalog waits for `migrate: service_completed_successfully` and healthy redis; the gateway for healthy
      catalog and redis; the storefront for the gateway, and for Copilot with `required: false` (skipped when that profile is off).
    - Every service has a `mem_limit` and a `pids_limit`.

11. Start everything and wait for healthy:

    ```bash
    docker compose up -d --wait
    docker compose ps -a --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"
    curl -s 127.0.0.1:8080/api/courses | jq -r ".[].title"
    ```

    ```
    SERVICE      STATUS                      PORTS
    catalog      Up 18 seconds (healthy)     8080/tcp
    db           Up 45 seconds (healthy)     5432/tcp
    gateway      Up 12 seconds (healthy)     8080/tcp
    migrate      Exited (0) 18 seconds ago
    redis        Up 45 seconds (healthy)     6379/tcp
    storefront   Up 7 seconds (healthy)      127.0.0.1:8080->8080/tcp
    DSA
    DevOps
    GenAI
    Spring Boot
    System Design
    ```

    Five courses, from PostgreSQL, through the real API. One published port.

### Step 5 - Profiles and the .env file

12. ```bash
    docker compose config --services
    cp .env.example .env && grep PROFILES .env
    docker compose config --services
    docker compose --profile debug config --services | tr "\n" " "; echo
    ```

    Six services without `.env`; seven once `COMPOSE_PROFILES=copilot` is set. A `--profile` flag replaces that variable,
    so with `--profile debug` netshoot and adminer join in, and Copilot drops out.

13. Start again with Copilot on, and ask it something through the storefront:

    ```bash
    docker compose up -d --wait
    curl -s "127.0.0.1:8080/copilot/ask?q=docker"; echo
    ```

    ```
    {"answer":"Try the DevOps course."}
    ```

### Step 6 - The Makefile

14. ```bash
    make help
    ```

    ```
    help      list the targets
    up        build what changed, start the stack, wait until healthy
    down      stop and remove containers of every profile (data stays)
    ps        status and health of every service
    logs      follow the logs: make logs s=catalog
    scan      Trivy gate on the local images
    registry  local registry on 127.0.0.1:5001 (stands in for GHCR or ECR)
    release   build, scan, SBOM, tag and push: make release VERSION=1.0.0
    nuke      DANGER: also delete the database volume and local images
    ```

    `make up` creates `.env` and the secret if they are missing, then runs `docker compose up -d --build --wait`.
    `make down` removes the containers of every profile and keeps the data. `make nuke` deletes the volume.

### Step 7 - Releases

15. Read `scripts/scan.sh` (Trivy 0.76.0 pinned by digest, `--severity CRITICAL --ignore-unfixed --exit-code 1`) and
    `scripts/release.sh` (refuses a non-semver version and uncommitted changes; builds every image once tagged
    `sha-<short commit>` with three OCI labels; runs the gate; Syft writes an SPDX SBOM per image; adds `1.0.0`, `1.0`, `1`;
    pushes; records the digests). Your work tree must be clean, so commit first if you changed anything.

16. Release (this also starts the local registry, `registry:3.1.2` on `127.0.0.1:5001`):

    ```bash
    git log --oneline -1
    time make release VERSION=1.0.0
    ```

    ```
    == 1/5 build sha-c781ca3
    == 2/5 gate: no fixable CRITICAL vulnerabilities
    PASS  localhost:5001/do-m07b01/storefront:sha-c781ca3
    PASS  localhost:5001/do-m07b01/gateway:sha-c781ca3
    PASS  localhost:5001/do-m07b01/catalog:sha-c781ca3
    PASS  localhost:5001/do-m07b01/copilot:sha-c781ca3
    == 3/5 SBOMs
    == 4/5 tag and push: sha-c781ca3 1.0.0 1.0 1
    == 5/5 digests (deploy these, not tags)
    localhost:5001/do-m07b01/storefront@sha256:...
    ```

    Your commit hash will differ. About 2 minutes in the video (mostly Trivy and Syft). Deploy the digests, not tags.
    Vulnerability databases change daily: if a base image has gained a fixable CRITICAL since the recording, the gate
    will (correctly) say FAIL.

17. Check what was pushed:

    ```bash
    curl -s 127.0.0.1:5001/v2/do-m07b01/catalog/tags/list; echo
    docker image inspect localhost:5001/do-m07b01/catalog:1.0.0 --format '{{json .Config.Labels}}' \
      | jq 'with_entries(select(.key|startswith("org.opencontainers")))'
    jq '.packages | length' dist/sbom/catalog-1.0.0.spdx.json
    jq -r '.packages[].name' dist/sbom/catalog-1.0.0.spdx.json | grep -E '^(spring-boot|postgresql|lettuce-core)$'
    ```

    Four tags (`1`, `1.0`, `1.0.0`, `sha-...`), the three OCI labels (full commit, source, version `1.0.0`), and an SBOM
    with 143 packages in the video, including `spring-boot`, `postgresql` and `lettuce-core` (the Redis client).

### Priya's first day: a fresh clone

18. Make it a true first run: delete everything the project built (images, volumes, build caches). The registry keeps
    running; it plays the team registry.

    ```bash
    docker compose --profile "*" down -v --rmi local
    docker image ls 'localhost:5001/do-m07b01/*' --format '{{.Repository}}:{{.Tag}}' | xargs docker rmi
    docker buildx prune -f --filter 'description~=do-m07b01'
    ```

19. Clone and start with one command:

    ```bash
    mkdir -p ~/priya && cd ~/priya
    git clone ~/allcsvideos-git/allcsvideos-platform.git
    cd allcsvideos-platform && ls
    time make up
    ```

    ```
    cp .env.example .env
    scripts/dev-secrets.sh
    created secrets/db_password.txt (random, local only)
    docker compose up -d --build --wait
    ...
     ✔ Container do-m07b01-storefront-1 Healthy    24.4s

    real	1m46.932s
    ```

    Maven downloads the dependencies (about 40 s per Java service), then the stack starts in health order. Most of the
    time is a one-time download; your time depends on your network.

20. Check it:

    ```bash
    make ps
    curl -s 127.0.0.1:8080/api/courses | jq -c ".[]"
    curl -s "127.0.0.1:8080/copilot/ask?q=kubernetes"; echo
    curl -s 127.0.0.1:8080/copilot/health; echo
    ```

    Six services healthy, `migrate` `Exited (0)`, five courses as JSON, and `{"answer":"Try the DevOps course."}`.
    Open <http://127.0.0.1:8080> in a browser: five courses with prices and seats, the Copilot box, and a footer that
    says which catalog container answered.

21. Is the cache working?

    ```bash
    curl -s -o /dev/null 127.0.0.1:8080/api/courses
    docker compose logs catalog | grep -oE "(No cache entry|Cache entry|Creating cache entry) .*"
    docker compose exec redis redis-cli info stats | grep keyspace
    docker compose exec redis redis-cli ttl "courses::SimpleKey []"
    ```

    ```
    No cache entry for key 'SimpleKey []' in cache(s) [courses]
    Creating cache entry for key 'SimpleKey []' in cache(s) [courses]
    Cache entry for key 'SimpleKey []' found in cache(s) [courses]
    Cache entry for key 'SimpleKey []' found in cache(s) [courses]
    keyspace_hits:2
    keyspace_misses:1
    (integer) 18
    ```

    Your counts depend on how many requests you made (the browser makes some too).

### Break it on purpose

22. **Stage 1: kill the database container.**

    ```bash
    curl -s -o /dev/null -w "%{http_code}\n" 127.0.0.1:8080/api/courses
    docker compose kill db
    docker compose ps -a db --format "table {{.Service}}\t{{.Status}}"
    curl -s -o /dev/null -w "%{http_code}\n" 127.0.0.1:8080/api/courses
    ```

    `db  Exited (137)`, and Docker does **not** restart it: a killed container counts as stopped by hand. Yet the API still
    answers `200`: the course list is in Redis for the rest of its 60 seconds.

23. Wait a minute or so, then:

    ```bash
    docker compose ps catalog gateway --format "table {{.Service}}\t{{.Status}}"
    curl -s -w "\n%{http_code} in %{time_total}s\n" 127.0.0.1:8080/api/courses
    docker compose logs gateway | grep -oE "GET /api/courses -> .*" | tail -3
    docker inspect do-m07b01-catalog-1 --format '{{(index .State.Health.Log 0).Output}}'
    ```

    ```
    catalog   Up 2 minutes (unhealthy)
    gateway   Up 2 minutes (healthy)
    {"cause":"ResponseStatusException","message":"Catalog is unavailable. Please try again soon."}
    504 in 3.023434s
    ...
    probe: java.net.SocketTimeoutException: Read timed out
    ```

    The gateway's 3 s response timeout fired and its fallback answered. Reload the browser: the storefront shows that
    message in red, and the page stays up.

24. The fix is just `make up`: Compose starts db, runs migrate again (nothing to migrate), and waits for healthy.

    ```bash
    make up
    docker compose ps catalog db --format "table {{.Service}}\t{{.Status}}"
    curl -s -o /dev/null -w "%{http_code}\n" 127.0.0.1:8080/api/courses
    ```

25. **Stage 2: a real crash.** Stop Postgres without a clean shutdown, from inside:

    ```bash
    docker compose exec db pg_ctl stop -m immediate -D /var/lib/postgresql/18/docker; echo
    docker compose ps db --format "table {{.Service}}\t{{.Status}}"
    ```

    A few seconds later:

    ```bash
    docker compose ps db catalog --format "table {{.Service}}\t{{.Status}}"
    docker inspect do-m07b01-db-1 --format 'restarts: {{.RestartCount}}, last exit code: {{.State.ExitCode}}'
    curl -s -o /dev/null -w "%{http_code}\n" 127.0.0.1:8080/api/courses
    ```

    This time Docker restarts it by itself (`health: starting`, then `healthy`, `restarts: 1`), and catalog stays healthy.
    The restart policy is for crashes.

26. **Stage 3: a bad release.** Pin an old `h11` in Copilot, commit, and release:

    ```bash
    echo "h11==0.14.0" >> copilot/requirements.txt
    git commit -qam "Copilot: pin h11 like the old prototype"
    make release VERSION=1.0.1
    curl -s 127.0.0.1:5001/v2/do-m07b01/copilot/tags/list; echo
    ```

    ```
    FAIL  localhost:5001/do-m07b01/copilot:sha-...
          h11 0.14.0  CVE-2025-43859  fixed in 0.16.0
    release 1.0.1 stopped: nothing was pushed
    {"name":"do-m07b01/copilot","tags":["1","1.0","1.0.0","sha-c781ca3"]}
    ```

27. Revert and release again:

    ```bash
    git revert --no-edit HEAD | head -1
    make release VERSION=1.0.1 2>&1 | grep -E "^(==|PASS|FAIL)"
    curl -s 127.0.0.1:5001/v2/do-m07b01/copilot/tags/list; echo
    for t in 1.0.0 1.0.1 1.0; do docker buildx imagetools inspect localhost:5001/do-m07b01/copilot:$t --format "$t {{.Manifest.Digest}}" | cut -c1-30; done
    ```

    Four times PASS. `1.0.1` now exists, `1.0` moved to the same digest as `1.0.1`, and `1.0.0` stays where it was.

28. **Stage 4: the data.** Add a course straight into the database, then `make down` and `make up`:

    ```bash
    docker compose exec db psql -U catalog -c "INSERT INTO courses VALUES ('K8S-101', 'Kubernetes', 49, 30)"
    make down 2>&1 | tail -2
    docker volume ls -q --filter name=do-m07b01_
    make up 2>&1 | tail -1
    curl -s 127.0.0.1:8080/api/courses | jq -r ".[].title" | tr "\n" " "; echo
    ```

    The volume `do-m07b01_pgdata` stays, and the list has six courses, Kubernetes included. (If you see five, the old list
    is still in the Redis cache: wait 60 s.)

29. `make nuke` is `down -v`: the volume goes.

    ```bash
    make nuke 2>&1 | grep -E "Volume.*Removed"
    make up 2>&1 | tail -1
    curl -s 127.0.0.1:8080/api/courses | jq -r ".[].title" | tr "\n" " "; echo
    ```

    ```
     Volume do-m07b01_pgdata Removed
    DSA DevOps GenAI Spring Boot System Design
    ```

    migrate seeded a fresh database and Kubernetes is gone. Only a backup brings data back.

### At real scale

- One host is one point of failure. Compose does not move containers to another machine and does not restart unhealthy ones; Kubernetes does (Modules 13-15).
- Images should not come from a laptop: CI builds, scans and pushes them on every commit (Module 8); promotion between environments (Module 9).
- Secrets should not be files on a disk: a secrets manager like Vault (Module 18), and signed images.
- The database becomes a managed service like Amazon RDS, with real backups (Module 10).

## Common mistakes
- **Expecting `restart: unless-stopped` to bring back a killed container.** `docker compose kill` counts as stopped by hand; the policy only restarts crashes. Run `make up` to bring it back.
- **Expecting Compose to restart an unhealthy container.** It does not; health only gates start-up order (and `--wait`). Kubernetes acts on health.
- **Putting the DB password in `environment:`.** Use a Compose secret (a file under `/run/secrets`), and Spring's `configtree` to read it.
- **Letting the app run migrations on start.** Here `migrate` owns the schema and catalog has Flyway off; catalog waits for `service_completed_successfully`.
- **nginx `proxy_pass http://gateway:8080` with a fixed name.** nginx resolves it once at start and keeps that IP; use `resolver 127.0.0.11` and a variable.
- **`make nuke` / `docker compose down -v` when you meant `make down`.** `-v` deletes the database volume.
- **Releasing with uncommitted changes, or without an `origin` remote.** `release.sh` refuses the first, and needs the second for its labels.
- **Port 5000 on macOS.** AirPlay uses it; the local registry is on `127.0.0.1:5001`.

## Clean up

```bash
cd ~/priya/allcsvideos-platform && make nuke
docker rm -f do-m07b01-registry
docker volume rm do-m07b01-registry-data do-m07b01-trivy-cache
docker image ls 'localhost:5001/do-m07b01/*' --format '{{.Repository}}:{{.Tag}}' | xargs docker rmi
docker buildx prune -f --filter 'description~=do-m07b01'
rm -rf ~/priya ~/allcsvideos-lab ~/allcsvideos-git
```

The public images (`postgres`, `redis`, `maven`, `trivy`, `syft`...) stay; remove them with `docker rmi` if you need the space.

## Extensions to try
- Add enrollment, payment and Kafka in a new profile.
- Put TLS in front of the storefront.
- Swap Copilot's keyword index for the real model service from the GenAI course (Module 17).
- Script a nightly backup of the `pgdata` volume.

## Next
[M08-L01 · What CI Is](../../ci/m08-l01-what-ci-is/)
