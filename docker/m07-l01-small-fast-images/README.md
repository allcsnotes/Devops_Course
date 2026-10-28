# M07-L01 · Small, Fast Images
> Video: Module 7, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- How multi-stage builds ship "the table, not the workshop": build with every tool, then `COPY --from` only the jar, the venv or the static files into a small runtime stage.
- How the base image (full, slim, Alpine, distroless, scratch) is the biggest size lever, and what each step down costs you.
- How to order steps (dependencies before source), use BuildKit cache mounts, and split a Spring Boot jar into layers so a rebuild takes seconds and a push uploads kilobytes.
- How `--target` builds a test stage, and how `FROM --platform=$BUILDPLATFORM` keeps multi-platform builds fast.
- How to debug an image that has no shell (`docker debug`, or a busybox sidecar).

## Before you start
- Docker Desktop with BuildKit (the video used Docker Desktop 4.79, engine 29.5.3, BuildKit v0.30.0, on Apple silicon).
- For the multi-platform step: Docker Desktop's **containerd image store** turned on (Settings > General).
- `curl` and a terminal (bash or zsh; on Windows use WSL or Git Bash).
- Helpful background: [M06-L02 Images, Layers and Registries](../m06-l02-images-layers-and-registries/) (layers and the cache) and [M06-L04 The Dockerfile, Line by Line](../m06-l04-the-dockerfile-line-by-line/) (Course Copilot's first Dockerfile).
- Disk space: the full-size images in this lesson add up to several GB. The clean-up section removes them.

Everything is pinned exactly as in the video: `maven:3.9.16-eclipse-temurin-25`, `eclipse-temurin:25.0.4.1_1-jre` / `_1-jdk`,
`gcr.io/distroless/java25-debian13:nonroot@sha256:a26596c2…`, `python:3.12.15` / `-slim` / `-alpine3.23`, `debian:13.7-slim`,
`gcr.io/distroless/python3-debian13:nonroot@sha256:ed91505d…`, `node:22.23.3-slim`, `nginx:1.29.8-alpine`,
`golang:1.26.5-alpine3.23`, `busybox:1.37.0`.

## Files in this folder

| Path | What it is |
|------|------------|
| `api/` | The allcsvideos API code from the Spring Boot course. Only `gateway/` is built here. |
| `api/Dockerfile.single` | v1: one stage. Builds and runs inside the Maven image. |
| `api/Dockerfile.multi` | v2: two stages. Dependencies first, then source; runs on the Temurin JRE. |
| `api/Dockerfile` | v3: cache mounts for `~/.m2`, a layered jar, base images as build args. |
| `copilot/` | Course Copilot (FastAPI) from M06-L04, plus `tests/` and `requirements-dev.txt`. |
| `copilot/Dockerfile.full` / `Dockerfile.l04` | The M06-L04 Dockerfile on the full base / on slim (as written in M06-L04). |
| `copilot/Dockerfile` | Three stages: `build` (venv + pip cache mount), `test` (pytest), `runtime` (slim). |
| `copilot/Dockerfile.distroless-try1` | Distroless, broken on purpose: keeps the shell entrypoint script. |
| `copilot/Dockerfile.distroless` | Distroless, fixed: exec form only, no wrapper script. |
| `copilot/Dockerfile.alpine` | The same multi-stage shape on Alpine (musl). |
| `storefront/` | A tiny Vite 8.3.4 site. `Dockerfile.single` serves it with Node; `Dockerfile` builds with Node, serves with nginx. |
| `pinger/` | A tiny Go uptime checker. `Dockerfile.broken` is scratch without CA certs or time zones; `Dockerfile` fixes both. |

Image names used below: `small/api`, `small/copilot`, `small/web`, `small/pinger`. Cache mount ids: `small-m2`, `small-pip`, `small-npm`.

## Follow along

### Part 1 - The API gateway (Java)

1. Go into the API folder and build **v1, single stage**, with no cache:

   ```bash
   cd api
   time docker build --no-cache --progress=plain -f Dockerfile.single -t small/api:1 .
   ```

   You should see Maven download about 700 files; Maven itself took about 21 s and the whole build about 28 s in the video.

2. Look at the size and where it comes from:

   ```bash
   docker image ls small/api
   docker history small/api:1
   ```

   ```
   IMAGE         ID             DISK USAGE   CONTENT SIZE
   small/api:1   0c4628f68f04       1.09GB          342MB
   ```

   Content size (342 MB) is the compressed download; disk usage (1.09 GB) adds the unpacked files. In `history`, the Maven
   step adds about 198 MB, and the JDK layer under it is 265 MB.

3. Priya's one-line change. Open `gateway/src/main/java/com/allcs/gateway/FallbackController.java` and change the message
   `Please try again soon.` to `Please try again in a minute.` Then rebuild v1:

   ```bash
   time docker build --progress=plain -f Dockerfile.single -t small/api:1 .
   ```

   The `COPY . .` layer changed, so Maven starts from nothing again: about 700 downloads, about 25 s.

4. Put the message back to `soon`, then build **v2, two stages**, with no cache:

   ```bash
   time docker build --no-cache --progress=plain -f Dockerfile.multi -t small/api:2 .
   ```

   The cold build is slower (about 37 s): `dependency:go-offline` also fetches every Maven plugin (about 1,230 downloads).

5. Make the same one-line change (`soon` -> `in a minute`) and rebuild v2:

   ```bash
   time docker build --progress=plain -f Dockerfile.multi -t small/api:2 .
   docker image ls small/api
   docker history small/api:2
   ```

   The pom layers and go-offline are `CACHED`; only `package` runs (about 2.2 s), about 6 s in total. The image drops to
   about 641 MB on disk: no Maven, no JDK, no source. The jar is one ~75 MB layer on top of the JRE.

6. Build **v3** (`Dockerfile`) once. This first build fills the `small-m2` cache mount:

   ```bash
   time docker build --progress=plain -t small/api:3 .
   ```

7. The limit of ordering: Priya adds the Prometheus metrics library. In `gateway/pom.xml`, add this as the first entry
   inside `<dependencies>`:

   ```xml
   		<dependency>
   			<groupId>io.micrometer</groupId>
   			<artifactId>micrometer-registry-prometheus</artifactId>
   		</dependency>
   ```

   Rebuild v3 (with the cache mount), then v2 (without it):

   ```bash
   time docker build --progress=plain -t small/api:3 .
   time docker build --progress=plain -f Dockerfile.multi -t small/api:2 .
   ```

   | Build after the pom change | go-offline downloads | Total time (video) |
   |---|---|---|
   | v3, cache mount | 20 (only the new files) | about 11 s |
   | v2, no cache mount | 1,248 (20 new, ~1,200 old) | about 40 s |

8. Look at the layered jar and its layer digests:

   ```bash
   docker history small/api:3 | head -n 8
   docker image inspect small/api:3 --format '{{join .RootFS.Layers "\n"}}' | tail -n 4
   ```

   ```
   COPY /layers/application/ ./ # buildkit         24.6kB
   COPY /layers/snapshot-dependencies/ ./ # bui…   4.1kB
   COPY /layers/spring-boot-loader/ ./ # buildk…   4.1kB
   COPY /layers/dependencies/ ./ # buildkit        78.1MB
   ```

9. Another code change: set the message to `Please try again in a few seconds.` Rebuild v3 and compare the digests:

   ```bash
   time docker build --progress=plain -t small/api:3 .
   docker image inspect small/api:3 --format '{{join .RootFS.Layers "\n"}}' | tail -n 4
   ```

   About 4.4 s. The first three digests are identical to step 8; only the last (tiny application) layer changed. A push
   would upload kilobytes.

10. Try other runtime bases through the build arg. Distroless has no version tags, so it is pinned by digest:

    ```bash
    docker build -q --build-arg RUNTIME_IMAGE=eclipse-temurin:25.0.4.1_1-jdk -t small/api:3-jdk .
    docker build -q \
      --build-arg RUNTIME_IMAGE=gcr.io/distroless/java25-debian13:nonroot@sha256:a26596c2d590343eda0ab66e67f089fd612ef3a3b972acf9e57c39f99f7a88c6 \
      -t small/api:3-distroless .
    docker image ls small/api
    ```

    ```
    small/api:3              641MB   185MB
    small/api:3-distroless   462MB   142MB
    small/api:3-jdk          758MB   219MB
    ```

11. Run it:

    ```bash
    docker run -d --name api -p 8080:8080 small/api:3
    docker logs api 2>&1 | grep Started
    curl -s localhost:8080/api/courses; echo
    curl -s localhost:8080/actuator/info; echo
    ```

    ```
    ... Started GatewayApplication in 1.461 seconds ...
    {"cause":"UnknownHostException","message":"Catalog is unavailable. Please try again in a few seconds."}
    {"version":"dev","environment":"local"}
    ```

    The fallback message is correct: the catalog service is not running here, so the gateway answers with its fallback.

12. See the cache mount. It is build cache, not image, so it never ships:

    ```bash
    docker buildx du --verbose --filter 'description~=small-m2'
    cd ..
    ```

    ```
    Size:         167.5MB
    Description:  cached mount /root/.m2 from exec /bin/sh -c mvn -B -f gateway/pom.xml dependency:go-offline with id "/small-m2"
    Type:         exec.cachemount
    ```

### Part 2 - Course Copilot (Python)

13. Compare the Python bases:

    ```bash
    cd copilot
    docker pull python:3.12.15 && docker pull python:3.12.15-slim && docker pull python:3.12.15-alpine3.23
    docker image ls --filter reference='python:3.12.15*'
    ```

    ```
    python:3.12.15              1.62GB    419MB
    python:3.12.15-alpine3.23   88.5MB   22.1MB
    python:3.12.15-slim          205MB   45.7MB
    ```

14. Build the M06-L04 Dockerfile on the full base and on slim:

    ```bash
    time docker build -q --no-cache -f Dockerfile.full -t small/copilot:full .
    time docker build -q --no-cache -f Dockerfile.l04 -t small/copilot:slim .
    ```

15. Build the three-stage `Dockerfile` (default target = the last stage, `runtime`):

    ```bash
    time docker build --no-cache --progress=plain --build-arg APP_VERSION=1.5.0 -t small/copilot:1.5.0 .
    docker image ls small/copilot
    ```

    In the build steps you only see `build` and `runtime`: BuildKit skipped the `test` stage, because the runtime does not
    need it. Sizes: `full` 1.65 GB, `slim` 259 MB, `1.5.0` 244 MB. Only 15 MB less than slim, honestly: every Copilot
    dependency ships as a ready-made wheel, so there was no compiler to leave behind.

16. Build the test stage instead. The tests run inside the build:

    ```bash
    docker build --progress=plain --target test -t small/copilot:test .
    ```

    You should see `2 passed`. In CI, a failing test fails the build before any image is pushed.

17. Run the runtime image:

    ```bash
    docker run -d --name copilot -p 8000:8000 small/copilot:1.5.0
    docker ps --filter name=copilot --format "{{.Names}}  {{.Status}}"
    curl -s localhost:8000/health; echo
    ```

    ```
    copilot  Up 9 seconds (healthy)
    {"status":"ok","version":"1.5.0","courses":5}
    ```

18. The attack surface: tools and package counts.

    ```bash
    docker run --rm --entrypoint which small/copilot:full gcc make git curl
    docker run --rm --entrypoint which small/copilot:1.5.0 gcc make git curl
    docker run --rm --entrypoint dpkg-query small/copilot:full -W | wc -l
    docker run --rm --entrypoint dpkg-query small/copilot:1.5.0 -W | wc -l
    docker history small/copilot:1.5.0 | head -n 14
    ```

    The full image has `gcc`, `make`, `git` and `curl`; the new one has none. Packages: 467 vs 87. The health check now
    uses a one-line Python call, so curl is gone too.

19. Which Python does distroless have? There is no 3.12:

    ```bash
    docker run --rm python:3.12.15-slim python --version
    D12=gcr.io/distroless/python3-debian12@sha256:2fdb05402a2cf21cf78fdb3ba4c5db167241e9e498140f5bf689d7efb773731f
    D13=gcr.io/distroless/python3-debian13@sha256:e8f62938f332884afc903083bd4e2b9e5f5dcd4084aac0db135ffc7c0025f2ce
    docker run --rm $D12 --version
    docker run --rm $D13 --version
    ```

    `3.12.15`, `3.11.2`, `3.13.5`. Distroless uses Debian's Python, so the build stage must match it exactly or the venv
    breaks. That is why `Dockerfile.distroless` builds on `debian:13.7-slim` with Debian's own `python3-venv`.

20. Break it on purpose: distroless with the shell entrypoint script.

    ```bash
    docker build -q -f Dockerfile.distroless-try1 -t small/copilot:distroless-try1 .
    docker run --rm small/copilot:distroless-try1; echo "exit $?"
    docker run --rm --entrypoint sh small/copilot:distroless-try1
    ```

    ```
    exec /app/docker-entrypoint.sh: no such file or directory
    exit 255
    ... exec: "sh": executable file not found in $PATH
    ```

    The file is there, but its first line asks for `/bin/sh`, and distroless has no shell.

21. The fix (`Dockerfile.distroless`): no wrapper script, exec form only, the venv's Python runs uvicorn directly.

    ```bash
    time docker build -q -f Dockerfile.distroless -t small/copilot:distroless .
    docker run -d --name copilot-dl -p 8001:8000 small/copilot:distroless
    docker ps --filter name=copilot-dl --format "{{.Names}}  {{.Status}}"
    curl -s localhost:8001/health; echo
    docker exec copilot-dl sh
    docker exec copilot-dl ls /bin
    ```

    Healthy, it answers `{"status":"ok","version":"dev","courses":5}`, and both `exec` calls fail with
    `executable file not found`: there is nothing to run but Python.

22. Count the distroless packages (no `dpkg-query` inside, so Python counts the status files):

    ```bash
    docker run --rm --entrypoint /opt/venv/bin/python3 small/copilot:distroless -c \
      "import os; print(sum(not f.endswith(\"md5sums\") for f in os.listdir(\"/var/lib/dpkg/status.d\")))"
    ```

    `38`, against 87 for slim and 467 for full.

23. Alpine, same multi-stage shape:

    ```bash
    time docker build --no-cache --progress=plain -f Dockerfile.alpine -t small/copilot:alpine .
    ```

    It works because `pydantic-core` ships a musllinux wheel. Not every package does:

    ```bash
    docker run --rm python:3.12.15-slim pip download -q \
      --disable-pip-version-check --no-deps -d /tmp onnxruntime==1.31.0; echo "exit $?"
    docker run --rm python:3.12.15-alpine3.23 pip download -q \
      --disable-pip-version-check --no-deps -d /tmp onnxruntime==1.31.0; echo "exit $?"
    ```

    ```
    exit 0
    ERROR: No matching distribution found for onnxruntime==1.31.0
    exit 1
    ```

24. The Copilot line-up:

    ```bash
    docker rmi small/copilot:distroless-try1 small/copilot:test
    docker image ls small/copilot
    ```

    ```
    small/copilot:1.5.0         244MB   52.8MB
    small/copilot:alpine        130MB   30.9MB
    small/copilot:distroless    143MB   31.5MB
    small/copilot:full         1.65GB    412MB
    small/copilot:slim          259MB   57.3MB
    ```

    Asha keeps multi-stage slim for now, and distroless as the hardened option.

25. Debugging an image with no shell. On Docker Desktop, `docker debug` attaches a toolbox shell without changing the image:

    ```bash
    docker debug --command "ps aux" copilot-dl
    ```

    On a server without Desktop, run a throwaway busybox that joins the container's process and network namespaces:

    ```bash
    docker run --rm --pid container:copilot-dl --network container:copilot-dl \
      busybox:1.37.0 sh -c "ps; wget -qO- localhost:8000/health"
    cd ..
    ```

    ```
    PID   USER     TIME  COMMAND
        1 65532     0:01 /opt/venv/bin/python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000
    {"status":"ok","version":"dev","courses":5}
    ```

### Part 3 - The storefront (static site)

26. v1 builds and serves with Node (`vite preview`); v2 only builds with Node and serves `dist/` from nginx:

    ```bash
    cd storefront
    time docker build -q -f Dockerfile.single -t small/web:1 .
    time docker build --progress=plain -t small/web:2 .
    docker image ls small/web
    ```

    ```
    small/web:1    482MB    129MB
    small/web:2   91.8MB   25.8MB
    ```

27. Run v2 (nginx listens on port 80 inside):

    ```bash
    docker run -d --name web -p 8081:80 small/web:2
    curl -s localhost:8081 | head -n 6
    ```

    You should see the start of the HTML page, ending with `<title>allcsvideos - video courses</title>`.

28. Multi-platform build. The build stage has `FROM --platform=$BUILDPLATFORM`, so Node runs once, natively; only the
    nginx `COPY` runs for the other platform:

    ```bash
    time docker build --progress=plain --platform linux/amd64,linux/arm64 -t small/web:2-multi .
    docker image ls --tree small/web:2-multi
    cd ..
    ```

    ```
    small/web:2-multi   118MB   51.8MB
    ├─ linux/amd64       26MB     26MB
    └─ linux/arm64     91.8MB   25.8MB
    ```

    About 3.8 s in the video: every Node step was `CACHED` from the build a minute earlier. (On an Intel/AMD laptop the
    native platform is amd64 and the arm64 variant is the extra one.)

### Part 4 - scratch (Go)

29. A static Go binary in an empty image:

    ```bash
    cd pinger
    docker build -q -f Dockerfile.broken -t small/pinger:1 .
    docker run --rm small/pinger:1
    ```

    ```
    timezone error: unknown time zone Asia/Kolkata
    check failed: Get "https://example.com/": tls: failed to verify certificate: x509: certificate signed by unknown authority
    ```

    scratch is empty: no CA certificates, no time zone database.

30. The fix: copy the CA bundle from the build stage and build with `-tags timetzdata`:

    ```bash
    docker build -q -t small/pinger:2 .
    docker run --rm small/pinger:2
    docker image ls small/pinger
    cd ..
    ```

    ```
    Mumbai time: 22:23 IST
    https://example.com/ -> 200 OK
    small/pinger:1   12.2MB   4.34MB
    small/pinger:2     13MB   4.54MB
    ```

### Part 5 - Everything side by side

31. ```bash
    docker image ls --filter reference='small/*'
    ```

    | Service | Variant | Disk usage |
    |---|---|---|
    | API | single stage / JRE / JDK / distroless | 1.1 GB / 641 MB / 758 MB / 462 MB |
    | Copilot | full / M06-L04 slim / multi-stage / distroless / Alpine | 1.65 GB / 259 MB / 244 MB / 143 MB / 130 MB |
    | Storefront | Node / nginx | 482 MB / 91.8 MB |
    | Pinger | scratch broken / fixed | 12.2 MB / 13 MB |

    | API rebuild | v1 single | v2 multi | v3 cache mount + layered jar |
    |---|---|---|---|
    | code change | ~25 s | ~6 s | ~4.4 s |
    | pom change | - | ~40 s | ~11 s |

Your times will differ with your machine and network; the ratios are what matters.

## Common mistakes
- **Chasing the smallest image and losing the ability to debug it.** With no shell, `docker exec` gives you nothing. Use `docker debug` (Docker Desktop) or a busybox sidecar that joins the container's PID and network namespaces.
- **Alpine with Python.** musl is not glibc. Some wheels do not exist for musl (e.g. `onnxruntime`), so pip compiles from source (slow, needs compilers) or fails. Measure before you switch.
- **scratch and distroless only have what you put there.** CA certificates, time zone data, a non-root user. Test the real behaviour, not just that it starts.
- **A shell-script entrypoint on distroless.** `#!/bin/sh` needs a shell. Use the exec form and call the program directly.
- **A distroless build stage with a different Python.** The venv must be built with the exact same Python version and path as the runtime.
- **Copying build tools into the runtime.** `COPY . .` in the last stage, or copying a whole build-stage folder, brings the workshop back. `docker history` will show it.
- **Source before dependencies.** If `COPY . .` comes before the dependency download, every code change re-downloads everything.

## Clean up

```bash
docker rm -f api copilot copilot-dl web
docker image ls --filter reference='small/*' -q | sort -u | xargs docker rmi -f
docker buildx prune -f --filter 'description~=small-m2'
docker buildx prune -f --filter 'description~=small-pip'
docker buildx prune -f --filter 'description~=small-npm'
```

The public base images (`maven`, `python`, `node`, `nginx`, `golang`, distroless...) stay; remove them with
`docker rmi <image>` if you need the disk space. If you edited files in `api/gateway/`, you can restore them with
`git checkout -- api/gateway` from the repo root.

## Next
[M07-L02 · Docker Compose](../m07-l02-docker-compose/)
