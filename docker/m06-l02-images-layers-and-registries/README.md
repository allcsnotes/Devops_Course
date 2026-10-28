# M06-L02 · Images, Layers and Registries
> Video: Module 6, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- Image vs container: the class and the object. An image is read-only layers + a config + a manifest; an index picks the manifest for your platform
- How to read an image name: registry / namespace / repository : tag, and how a digest (`@sha256:...`) pins exact bytes
- How the build cache works: change one Dockerfile step and every step after it is rebuilt
- Copy-on-write with overlay: a container writes only into its own thin layer (`docker diff`), and deleting in a later layer never shrinks an image
- Running your own registry, pushing and pulling only the missing blobs, and why `latest` is not a deploy strategy
- `docker save`/`load`, Docker Hub pull limits, safe pruning, and why secrets must never go into a layer

## Before you start
- Docker Desktop (the video used 4.79, engine 29.5.3, which uses the containerd image store) or Docker Engine on Linux.
- `curl` (on Windows PowerShell, type `curl.exe`).
- Images used, all pinned: `alpine:3.23.6`, `python:3.13.16-alpine3.23`, `nginx:1.29.8-alpine`, `registry:3.1.2`.
- Helpful background: [M06-L01](../m06-l01-vms-vs-containers/) (overlay root filesystem, the 8 nginx layers).

In the video the images are named `localhost:5001/do-m06l02/...` and the containers `do-m06l02-web` / `do-m06l02-registry`. Here they are `localhost:5001/allcsvideos/...`, `web` and `registry`. The label `lesson=m06l02` is kept: it is how you clean up safely at the end.

Your digests and image IDs will differ from the video wherever you build something yourself or run on a different CPU (amd64 vs arm64). The pattern is what matters.

## Files in this folder
| File | What it is |
|---|---|
| `storefront/Dockerfile` | The storefront image: `FROM nginx:1.29.8-alpine`, `RUN apk add --no-cache jq`, `COPY site/` |
| `storefront/site/index.html` | The home page (version 1.0). You edit it in step 6 |
| `status/Dockerfile`, `status/index.html` | A second image on the same nginx base, to show shared layers |
| `bloat/Dockerfile` | Staged mistake: one RUN writes 50 MB, the next RUN deletes it |
| `bloat-fixed/Dockerfile` | The fix: create and delete in the same RUN |
| `secret/Dockerfile` | Staged mistake with a **FAKE** token in an ENV line, "removed" later |
| `reference/*.json` | Real index, arm64 manifest and `image inspect` output of `python:3.13.16-alpine3.23`, to read what an index, manifest and config look like |

## Follow along

### 1. Pull, and watch layers get shared
```bash
docker pull alpine:3.23.6
docker pull python:3.13.16-alpine3.23
docker pull python:3.13.16-alpine3.23
```
The second pull of Python ends with `Status: Image is up to date`. Now compare the layer lists:
```bash
docker image inspect alpine:3.23.6 --format '{{json .RootFS.Layers}}'
docker image inspect python:3.13.16-alpine3.23 --format '{{json .RootFS.Layers}}'
```
Alpine has one layer (`sha256:189320...` in the video). Python has four, and its **first** layer is the same one: Docker skipped downloading it because it was already on disk.

### 2. List images, and see that a tag is just a pointer
```bash
docker image ls alpine
docker pull nginx:1.29.8-alpine
docker tag nginx:1.29.8-alpine nginx:1.29-alpine     # the video already had this second tag on the machine
docker image ls nginx
```
```
IMAGE           ID             DISK USAGE   CONTENT SIZE
alpine:3.23.6   85fe1e81d675       13.6MB         4.27MB
nginx:1.29-alpine     5616878291a2       92.7MB         26.7MB
nginx:1.29.8-alpine   5616878291a2       92.7MB         26.7MB
```
Content size is the compressed download, disk usage adds the unpacked files. Two tags, one ID: two names, one image. (A `U` in the EXTRA column means a container uses it.)

### 3. Read the index, digests and config
```bash
docker buildx imagetools inspect nginx:1.29.8-alpine
```
This reads the index from Docker Hub without pulling anything. You should see one manifest per platform (linux/amd64, linux/arm/v6, linux/arm/v7, linux/arm64/v8, linux/386, linux/ppc64le, linux/riscv64, linux/s390x), each followed by an `unknown/unknown` attestation manifest (build provenance, not a runnable image).

```bash
docker image ls --digests nginx
docker pull nginx@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de
```
A tag can point to another image tomorrow; a name with a digest can only ever mean these exact bytes.

```bash
docker image inspect nginx:1.29.8-alpine --format '{{.Os}}/{{.Architecture}}'
docker image inspect nginx:1.29.8-alpine --format '{{json .Config.Cmd}}'
docker image inspect nginx:1.29.8-alpine --format '{{json .Config.Entrypoint}}'
docker image inspect nginx:1.29.8-alpine --format '{{json .Config.Env}}'
docker image inspect nginx:1.29.8-alpine --format '{{len .RootFS.Layers}} layers'
```
```
linux/arm64                      <- linux/amd64 on an Intel/AMD machine
["nginx","-g","daemon off;"]
["/docker-entrypoint.sh"]
["PATH=...","NGINX_VERSION=1.29.8", ...]
8 layers
```

### 4. How was the image built?
```bash
docker history nginx:1.29.8-alpine
```
Newest step on top. At the bottom: `ADD alpine-minirootfs-3.23.4-... 9.35MB`. One `RUN` installed nginx: `50.7MB`. `ENV`, `CMD`, `EXPOSE`, `LABEL` show `0B` (config only). `<missing>` is not an error: those steps were built on another machine.

### 5. Build your own image
```bash
cd storefront
docker build --progress=plain \
  --label course=devops --label lesson=m06l02 \
  -t localhost:5001/allcsvideos/storefront:1.0 .
```
You should see:
```
#5 [1/3] FROM docker.io/library/nginx:1.29.8-alpine@sha256:5616...
#5 CACHED
#6 [2/3] RUN apk add --no-cache jq
#6 1.318 (1/2) Installing oniguruma (6.9.10-r0)
#6 1.357 (2/2) Installing jq (1.8.2-r0)
#6 DONE 1.4s
#7 [3/3] COPY site/ /usr/share/nginx/html/
#7 DONE 0.0s
#8 exporting manifest sha256:...
#8 exporting config sha256:...
#8 exporting attestation manifest sha256:...
#8 exporting manifest list sha256:...
```
```bash
docker image ls localhost:5001/allcsvideos/storefront
docker history localhost:5001/allcsvideos/storefront:1.0
```
Two new layers on top: the COPY (`24.6kB`) and the RUN (`1.2MB`). Everything below is nginx, reused.

Build again with nothing changed:
```bash
docker build --progress=plain \
  --label course=devops --label lesson=m06l02 \
  -t localhost:5001/allcsvideos/storefront:1.0 .
```
Every step says `CACHED`, and the `exporting manifest` digest is the same as before. Only the manifest list changes, because each build attaches a fresh attestation with its own timestamps.

### 6. Change a late line, then an early line
Add one line to the end of `site/index.html`:
```html
<p>New: the DevOps course is live.</p>
```
```bash
docker build --progress=plain \
  --label course=devops --label lesson=m06l02 \
  -t localhost:5001/allcsvideos/storefront:1.1 .
```
The RUN is `CACHED`; only the COPY runs again.

Now change the RUN line in `Dockerfile` to `RUN apk add --no-cache jq bash` and build 1.2:
```bash
docker build --progress=plain \
  --label course=devops --label lesson=m06l02 \
  -t localhost:5001/allcsvideos/storefront:1.2 .
```
The RUN runs again (4 packages: readline, bash, oniguruma, jq), **and so does the COPY**, though the pages did not change. Rule: put what changes least at the top, what changes most at the bottom.

### 7. Layers are shared on disk too
```bash
cd ../status
docker build -q --label course=devops --label lesson=m06l02 \
  -t localhost:5001/allcsvideos/status:1.0 .
docker system df -v
```
In the images table, look at SIZE, SHARED SIZE and UNIQUE SIZE for your images. In the video: status 91.8MB total but only 41.33kB unique; storefront 1.2 has 6.38MB unique (jq plus bash). The nginx base is on disk once.

### 8. Copy-on-write: a container's own layer
```bash
docker run -d --name web --label course=devops \
  localhost:5001/allcsvideos/storefront:1.1
docker diff web
```
Even untouched, nginx has written things: `A /run/nginx.pid`, `A /var/cache/nginx/...`, `C /etc/nginx/conf.d/default.conf`. Now make three changes:
```bash
docker exec web sh -c 'echo note > /tmp/note.txt'
docker exec web rm /usr/share/nginx/html/50x.html
docker exec web sh -c 'echo "<p>edited live</p>" >> /usr/share/nginx/html/index.html'
docker diff web
```
New lines: `A /tmp/note.txt`, `C /usr/share/nginx/html/index.html`, `D /usr/share/nginx/html/50x.html` (D is a whiteout). The image is unchanged:
```bash
docker exec web tail -n 2 /usr/share/nginx/html/index.html
docker run --rm --label course=devops localhost:5001/allcsvideos/storefront:1.1 tail -n 2 /usr/share/nginx/html/index.html
```
The running container shows `<p>edited live</p>`; a fresh container shows the original page.

### 9. Deleting in a later layer saves nothing
```bash
cd ../bloat
docker build -q --label course=devops --label lesson=m06l02 \
  -t localhost:5001/allcsvideos/bloat:1.0 .
docker image ls localhost:5001/allcsvideos/bloat
docker history localhost:5001/allcsvideos/bloat:1.0
```
`118MB` on disk, `56.6MB` to download, for a file that is not there. History: the write is `52.4MB`, the delete is `4.1kB` (just a whiteout). The fix:
```bash
cd ../bloat-fixed
docker build -q --label course=devops --label lesson=m06l02 \
  -t localhost:5001/allcsvideos/bloat:1.1 .
docker image ls localhost:5001/allcsvideos/bloat
```
Version 1.1: `13.5MB`, the size of plain Alpine.

### 10. Secrets stay in the layers (FAKE token)
```bash
cd ../secret
docker build -q --label course=devops --label lesson=m06l02 \
  -t localhost:5001/allcsvideos/secret-demo:1.0 .
docker image inspect localhost:5001/allcsvideos/secret-demo:1.0 --format '{{json .Config.Env}}'
docker history localhost:5001/allcsvideos/secret-demo:1.0
cd ..
```
`inspect` shows `PAYMENT_API_TOKEN=` (empty, looks safe), but `history` still shows `ENV PAYMENT_API_TOKEN=FAKE-demo-token-7f3a9c`. Anyone who can pull the image can read it.

### 11. Run a private registry
The registry's default port is 5000:
```bash
docker run -d --name registry --label course=devops \
  -p 5000:5000 -v regdata:/var/lib/registry registry:3.1.2
```
On a Mac this fails with `bind: address already in use`: port 5000 belongs to the AirPlay Receiver. Remove the half-created container and use 5001 on the laptop:
```bash
docker rm registry
docker run -d --name registry --label course=devops \
  -p 5001:5000 -v regdata:/var/lib/registry registry:3.1.2
docker ps --filter name=registry --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
```
(If the first command worked for you, run `docker rm -f registry` and continue with 5001 anyway, so the image names match.)

### 12. Push, look at the API, pull back
```bash
docker push localhost:5001/allcsvideos/storefront:1.0
docker push localhost:5001/allcsvideos/storefront:1.1
```
The first push sends every blob (`Pushed`). The second shows `Layer already exists` for most and pushes only two: the new COPY layer and the new config.
```bash
curl -s localhost:5001/v2/_catalog
curl -s localhost:5001/v2/allcsvideos/storefront/tags/list
```
```
{"repositories":["allcsvideos/storefront"]}
{"name":"allcsvideos/storefront","tags":["1.0","1.1"]}
```
```bash
docker rmi localhost:5001/allcsvideos/storefront:1.0
docker pull localhost:5001/allcsvideos/storefront:1.0
```
Same digest as you pushed: what you push is exactly what you pull.

### 13. The `latest` trap, for real
Friday: Asha tags 1.0 as latest and pushes; staging pulls it.
```bash
docker tag localhost:5001/allcsvideos/storefront:1.0 localhost:5001/allcsvideos/storefront:latest
docker push localhost:5001/allcsvideos/storefront:latest
docker pull localhost:5001/allcsvideos/storefront:latest
```
Every layer already exists; only a tag is written. Note the digest (`948bfb...` in the video).

Weekend: Priya tags 1.1 as latest and pushes.
```bash
docker tag localhost:5001/allcsvideos/storefront:1.1 localhost:5001/allcsvideos/storefront:latest
docker push localhost:5001/allcsvideos/storefront:latest
```
Monday: production still has Friday's copy. Simulate that by pointing your local `latest` back at 1.0, then pull:
```bash
docker tag localhost:5001/allcsvideos/storefront:1.0 localhost:5001/allcsvideos/storefront:latest
docker pull localhost:5001/allcsvideos/storefront:latest
```
`Status: Downloaded newer image`, with a different digest (`3775a1...` in the video). Pull by Friday's digest instead (use the digest from your Friday pull):
```bash
docker pull localhost:5001/allcsvideos/storefront@sha256:<friday-digest>
docker run --rm --label course=devops localhost:5001/allcsvideos/storefront:latest tail -n 1 /usr/share/nginx/html/index.html
docker run --rm --label course=devops localhost:5001/allcsvideos/storefront@sha256:<friday-digest> tail -n 1 /usr/share/nginx/html/index.html
```
`latest` ends with the DevOps line; the digest gives Friday's page, byte for byte.

### 14. Images without a registry
```bash
docker save -o storefront-1.2.tar localhost:5001/allcsvideos/storefront:1.2
docker rmi localhost:5001/allcsvideos/storefront:1.2
docker load -i storefront-1.2.tar
rm storefront-1.2.tar
```
```
Loaded image: localhost:5001/allcsvideos/storefront:1.2
```

### 15. Prune safely, scoped by label
```bash
docker image ls --filter label=lesson=m06l02
docker image ls --filter dangling=true --filter label=lesson=m06l02
docker image prune -a -f --filter label=lesson=m06l02
docker image ls --filter label=lesson=m06l02
```
The dangling list is empty (the containerd image store doesn't leave untagged images behind on rebuild). The prune deletes every labelled image no container uses; `storefront:1.1` survives because `web` still uses it. **Never run `docker image prune -a` unscoped on a shared machine.**

## Common mistakes
1. **`latest` isn't latest.** It is just the default tag name, moved by whoever pushed last. Pin exact tags, and digests in production. Record the digest you tested.
2. **Huge images.** Every megabyte is pulled by every server on every deploy, and deleting in a later layer saves nothing (the 118 MB bloat image). Small bases and multi-stage builds come in module 7.
3. **Secrets baked into layers.** `docker history` shows every ENV step; a file copied in and deleted later is still inside its layer. Pass secrets at run time or use build secrets (modules 7 and 18).
4. **Pulling unverified images.** Prefer Docker Official Images and Verified Publishers, read the Dockerfile, pin the digest, scan what you pull (Trivy and cosign in modules 7 and 18).
5. **Docker Hub pull limits** (Docker docs, checked 2026-10-20): anonymous 100 pulls per 6 hours per IPv4 address or IPv6 /64; free personal account 200 per 6 hours; Pro, Team, Business unlimited. In CI: pin versions, log in, and mirror base images or run a pull-through cache.

## Clean up
```bash
docker rm -f web registry
docker volume rm regdata
docker image prune -a -f --filter label=lesson=m06l02
docker rmi localhost:5001/allcsvideos/storefront:1.0 localhost:5001/allcsvideos/storefront:latest 2>/dev/null
docker rmi localhost:5001/allcsvideos/storefront@sha256:<friday-digest> 2>/dev/null
docker rmi nginx:1.29-alpine           # only the extra tag you added in step 2
```
The base images (`alpine`, `python`, `nginx`, `registry`) are reused by later lessons; remove them with `docker rmi` only if you want the disk space back. If you edited `storefront/` in step 6, `git checkout -- storefront` restores it.

## Next
[M06-L03 · Running Containers](../m06-l03-running-containers/)
