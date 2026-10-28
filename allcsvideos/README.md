# allcsvideos platform

The whole allcsvideos platform on one machine, with one command. Built in DevOps course video
M07-B01 "Containerise the allcsvideos Stack", and the course's shared running-example repo from Module 8 on.

```sh
git clone <this repo> && cd allcsvideos-platform
make up                      # first run: creates .env and a random local DB password, builds, waits for healthy
open http://127.0.0.1:8080   # the storefront
```

Needs Docker with Compose v2.20 or newer (tested with Docker Desktop 4.79, engine 29.5.3, Compose v5.1.4) and `make`.

## What runs

| Service    | What it is                                                                 | Networks     | Host port       |
|------------|----------------------------------------------------------------------------|--------------|-----------------|
| storefront | Vite site on unprivileged nginx 1.29.8; proxies `/api/` and `/copilot/`    | front        | 127.0.0.1:8080  |
| gateway    | Spring Cloud Gateway (Spring Boot course): routes `/api/courses`, circuit breaker + fallback, Redis rate limiter | front, back | none |
| catalog    | catalog-service (Spring Boot course): courses from PostgreSQL, list cached in Redis for 60 s | back | none |
| migrate    | one-off job: Flyway 12.4.0 applies `api/catalog-service/src/main/resources/db/migration`, then exits 0 | back | none |
| db         | postgres:18.6-alpine3.24, data in the named volume `pgdata`                | back         | none            |
| redis      | redis:8.10.2-alpine3.23, cache only (nothing saved to disk)                | back         | none            |
| copilot    | Course Copilot (FastAPI): keyword answers from a course index, **no AI model in this stack**. Profile `copilot` | front | none |
| netshoot, adminer | debug tools. Profile `debug` (adminer on 127.0.0.1:8081)            | front, back  | 8081 (adminer)  |

Start order is health-gated: db healthy -> migrate completed successfully -> catalog healthy (redis healthy) -> gateway
healthy -> storefront. `back` is `internal: true`: no route out, and the storefront cannot reach the database.

Not in this stack yet: the enrollment and payment services of the Spring Boot course. They run a Kafka saga, so catalog
starts with its Kafka listener and topic creation switched off (the same settings its own integration test uses).

## Production-minded defaults

- Multi-stage Dockerfiles, pinned base images: Java services on distroless Java 25 (`nonroot`, pinned by digest, AOT
  cache), Copilot on python:3.12.15-slim as uid 10001, storefront on nginx-unprivileged as uid 101.
- Every long-running service: `read_only: true`, `tmpfs: /tmp`, `cap_drop: [ALL]`, `no-new-privileges`, a memory and
  PID limit, `restart: unless-stopped`, and a health check (distroless images use a tiny Java probe, `api/probe`).
- Postgres runs as uid 70 and Redis as uid 999, not root.
- The DB password is a Compose secret (`secrets/db_password.txt`, git-ignored, random per laptop). Catalog reads it
  through Spring's configtree (`/run/secrets/spring.datasource.password`); Postgres and Flyway read the file.
- nginx resolves `gateway` and `copilot` per request (Docker DNS, 10 s cache): a recreated container is found, and the
  storefront starts even when the `copilot` profile is off.
- Redis is only a cache: if it is down, catalog logs a warning and reads PostgreSQL.

## Commands

```sh
make help                    # list the targets
make up                      # build what changed, start, wait until every service is healthy
make ps                      # status and health
make logs s=catalog          # follow one service
make down                    # remove containers of every profile; the database volume stays
make scan                    # Trivy gate on the local images (fails on a fixable CRITICAL)
make release VERSION=1.0.0   # build, gate, SBOMs, tag sha-<commit> + 1.0.0 + 1.0 + 1, push, record digests
make nuke                    # DANGER: down -v --rmi local, the database is deleted
docker compose --profile debug up -d   # add netshoot and adminer
```

`COMPOSE_PROFILES=copilot` in `.env` turns Course Copilot on; leave it empty for the core stack only.

## Releases

`scripts/release.sh VERSION` (via `make release`):

1. builds every image once, tagged `localhost:5001/do-m07b01/<service>:sha-<short commit>`, with OCI labels
   `org.opencontainers.image.revision`, `.source` and `.version`;
2. gates it: `scripts/scan.sh` runs Trivy 0.76.0 (pinned by digest) with `--severity CRITICAL --ignore-unfixed
   --exit-code 1`; one failure stops the release before anything is pushed;
3. writes SPDX SBOMs with Syft 1.54.1 (pinned by digest) to `dist/sbom/`;
4. adds the semver ladder (`1.0.0`, `1.0`, `1`) to the same image and pushes every tag;
5. writes the pushed digests to `dist/release-VERSION.txt`: deploy those, not tags.

`make registry` starts the local registry (registry:3.1.2 on 127.0.0.1:5001, macOS keeps port 5000 for AirPlay). It
stands in for GHCR or ECR; Module 8 moves the build into CI.

## Data

`make down` / `docker compose --profile "*" down` keeps the `pgdata` volume. `down -v` (`make nuke`) deletes it: the
next `make up` starts an empty database and the migrate job seeds it again. Real data only comes back from a backup.

## Limits of this setup

One host: no failover, no rolling updates, no autoscaling (Kubernetes, Modules 13-15). Images are built on a laptop
(CI, Module 8). Secrets are files on disk (a secrets manager, Module 18).

## Course naming

Everything is prefixed `do-m07b01` and labelled `course=devops` (project name, image names, cache mount ids, volumes).
Later videos copy this repo and rename the prefix to their own video id.

## Measured in M07-B01 (2026-10-21, Docker Desktop 4.79 on Apple silicon)

- Fresh clone, project images and Maven/npm/pip caches deleted, public base images already pulled:
  `time make up` = 1m46.9s (Maven dependency download about 41 s per Java service), then all 6 services healthy.
- `make release VERSION=1.0.0` with warm caches: 2m0.7s (most of it Trivy and Syft).
- Killing the db container: Docker does not restart a killed container; the cached course list kept answering for its
  60 s lifetime, then `/api/courses` returned 504 with the gateway fallback in about 3 s, and catalog turned unhealthy.
  `make up` brought db back. A real crash (`pg_ctl stop -m immediate`) is restarted by `restart: unless-stopped`.
