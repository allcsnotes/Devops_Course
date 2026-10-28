# M07-L04 · Registries and Tagging
> Video: Module 7, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- Why deploying `latest` breaks traceability and rollback, and how commit-SHA tags, a semver ladder (`1.4.2`, `1.4`, `1`) and digests fix it.
- Build once, tag the same digest several ways, and add OCI labels (`revision`, `source`, `version`) that lead back to the commit.
- Immutable tags: what goes wrong when a release tag is re-pushed, and where registries can (ECR) or cannot enforce it.
- Promote a tested digest between registries instead of rebuilding; deploy by digest.
- Registry access: tokens with `--password-stdin`, read-only accounts for servers, push only from CI, credential helpers.
- Multi-arch image indexes with annotations, and retention: cleanup rules, manifest deletes and garbage collection.

## Before you start
- Docker Desktop (the video used engine 29.5.3 with buildx 0.34.1), `git`, `curl`, `jq` and `python3`.
- The ideas from [M06-L02](../m06-l02-images-layers-and-registries/) (tags vs digests, the CNCF registry) and semantic versioning from Module 5.
- Free ports **5001** (the CI registry; macOS keeps 5000 for AirPlay Receiver) and **3000** (Gitea).
- About 1 GB of disk for the Gitea, registry, Python and BuildKit images.

The video runs two real registries on the laptop: the **CNCF registry** (`registry:3.1.2`, "the CI registry") and **Gitea 28.1.0**, whose built-in container registry has users, tokens and permissions like GHCR. `lab/up.sh` builds that lab for you. GHCR and ECR are shown as reference commands at the end; ECR is used for real in Module 10.

**Your hashes will differ.** Commit IDs and digests depend on the moment you build. The video's values (`1de47bf`, `758a92…`) are shown as examples; use your own everywhere.

## Files in this folder
| File | What it is |
|------|------------|
| `lab/up.sh` | Starts the registry and Gitea, creates users, org, teams and tokens, and the API's git history (v1.4.0, v1.4.1) |
| `lab/down.sh` | Removes the lab containers, volumes, tokens and the git repository |
| `lab/ci-history.sh` | Plays the CI pipeline before the retention step: pushes one `sha-<commit>` tag per commit to Gitea as `ci-bot` |
| `lab/buildkitd.toml` | BuildKit config for the multi-arch builder: `localhost:5001` speaks plain HTTP |
| `app/` | The API stand-in at version 1.4.0 (`app.py`, `Dockerfile`, `.dockerignore`, `.gitignore`); `up.sh` turns it into the git repo |
| `release/app.py` | The fix: `COPILOT_URL` becomes optional, version 1.4.2 |
| `release/release.sh` | Build once, tag `sha-<commit>`, `1.4.2`, `1.4`, `1`, `latest`, add OCI labels, push every tag |
| `lab/.tokens/` | Created by `up.sh`, git-ignored: the lab's access tokens (FAKE lab accounts), never printed |

## Follow along

### 0. Start the lab
```bash
cd Devops_Course/docker/m07-l04-registries-and-tagging      # this folder
export LESSON="$PWD"
bash lab/up.sh
```
At the end: three commits are pushed to Gitea, and `~/allcsvideos-api` is checked out at `v1.4.0`. You can open http://localhost:3000 and sign in as `asha` / `fake-lab-pass-asha` (a FAKE lab password).

Use **one terminal** for the whole lesson: later steps reuse variables (`LESSON`, `FRIDAY`, `SHA`, `DIGEST`, the tokens).

### 1. The hook: deploying `latest`
Friday: CI builds 1.4.0 and pushes it as `latest`. **Write down the digest it prints** (the video's started with `5ce50e`).
```bash
cd ~/allcsvideos-api
docker build -q -t localhost:5001/allcsvideos/api:latest .
docker push localhost:5001/allcsvideos/api:latest
FRIDAY=sha256:...        # paste the digest from the "latest: digest:" line
```
Monday: Priya's change (1.4.1) is built and pushed as `latest` again:
```bash
git checkout -q v1.4.1
docker build -q -t localhost:5001/allcsvideos/api:latest .
docker push localhost:5001/allcsvideos/api:latest
```
Two layers pushed, a new digest. Production deploys `latest`:
```bash
docker rmi localhost:5001/allcsvideos/api:latest      # play a fresh production server: nothing cached
docker run -d --name prod -p 127.0.0.1:8080:8080 localhost:5001/allcsvideos/api:latest
docker ps -a --filter name=prod --format '{{.Names}}  {{.Image}}  {{.Status}}'
docker logs prod 2>&1 | tail -4
```
```
prod  localhost:5001/allcsvideos/api:latest  Exited (1) 2 seconds ago
KeyError: 'COPILOT_URL'
```
The "rollback":
```bash
docker rm prod
docker pull localhost:5001/allcsvideos/api:latest
docker run -d --name prod -p 127.0.0.1:8080:8080 localhost:5001/allcsvideos/api:latest
docker ps -a --filter name=prod --format '{{.Names}}  {{.Image}}  {{.Status}}'
curl -s localhost:5001/v2/allcsvideos/api/tags/list
docker image inspect --format '{{json .Config.Labels}}' localhost:5001/allcsvideos/api:latest
```
`Image is up to date`, same digest, `Exited (1)` again. The registry has one tag (`["latest"]`) and the image has no labels (`null`). Friday's build is still in the registry, but nothing points to it.

### 2. The fix, as release v1.4.2
```bash
git checkout -q main
cp "$LESSON/release/app.py" "$LESSON/release/release.sh" .
git add app.py release.sh
git commit -qm 'fix: COPILOT_URL is optional; add release.sh'
git tag -a v1.4.2 -m 'api 1.4.2'
git -c http.extraHeader="Authorization: token $(cat "$LESSON/lab/.tokens/asha-cli")" push -q origin main --tags
git log --oneline --decorate
git rev-parse --short HEAD
git rev-parse HEAD
```
Three commits with tags `v1.4.0`, `v1.4.1`, `v1.4.2`; the short ID (7 characters) and the full 40.

### 3. Build once, tag three ways
Read `release.sh`: one `docker build` with three OCI labels (`source`, `revision` = the full commit, `version`), tagged `sha-<short commit>`. Then a loop adds `1.4.2`, `${VERSION%.*}` = `1.4`, `${VERSION%%.*}` = `1`, and `latest` with `docker tag` (nothing is rebuilt), and `docker push --all-tags` pushes them all.
```bash
./release.sh 1.4.2
curl -s localhost:5001/v2/allcsvideos/api/tags/list
SHA=$(git rev-parse --short HEAD)
for t in sha-$SHA 1.4.2 1.4 1 latest; do printf '%-12s' $t; docker buildx imagetools inspect --format '{{.Manifest.Digest}}' localhost:5001/allcsvideos/api:$t; echo; done
```
```
{"name":"allcsvideos/api","tags":["1","1.4","1.4.2","latest","sha-1de47bf"]}
sha-1de47bf sha256:758a92f84b21...
1.4.2       sha256:758a92f84b21...
1.4         sha256:758a92f84b21...
...
```
Five names, one image. The first push uploads only two new layers. Now the labels lead back to the code:
```bash
docker image inspect --format '{{json .Config.Labels}}' localhost:5001/allcsvideos/api:latest | jq
REV=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' localhost:5001/allcsvideos/api:latest)
git log -1 --format='%h  %an  %ad  %s' --date=short $REV
```

### 4. Deploy by digest
```bash
DIGEST=$(docker buildx imagetools inspect --format '{{.Manifest.Digest}}' localhost:5001/allcsvideos/api:1.4.2)
echo $DIGEST                     # write it down: this is what production runs
docker rm -f prod
docker run -d --name prod -p 127.0.0.1:8080:8080 localhost:5001/allcsvideos/api@$DIGEST
sleep 1; curl -s localhost:8080/whoami
docker inspect --format '{{.Config.Image}}' prod
```
`{"api": "...", "version": "1.4.2", "copilot": "http://copilot:8000"}`, and the container records the exact reference it runs. And Friday's build was there all along:
```bash
curl -s -o /dev/null -w '%{http_code}\n' -H 'Accept: application/vnd.oci.image.index.v1+json' localhost:5001/v2/allcsvideos/api/manifests/$FRIDAY
```
`200`. With its digest written down, Monday's rollback would have taken seconds.

### 5. Break immutability on purpose
Priya's quick tweak, built and pushed as `1.4.2` without the release script:
```bash
sed -i.bak 's/listening on/ready, listening on/' app.py && rm app.py.bak
docker build -q -t localhost:5001/allcsvideos/api:1.4.2 .
docker push localhost:5001/allcsvideos/api:1.4.2
for t in sha-$SHA 1.4.2; do printf '%-12s' $t; docker buildx imagetools inspect --format '{{.Manifest.Digest}}' localhost:5001/allcsvideos/api:$t; echo; done
curl -s localhost:8080/whoami
git checkout app.py
```
The registry accepts it without a word: `sha-…` is still the tested digest, `1.4.2` now names different, untested bytes without labels. Production does not care: it is pinned by digest. (ECR's `IMMUTABLE` setting would have refused this push; see the reference section.)

### 6. A registry with accounts (Gitea, like GHCR)
Images are named `host/owner/image`, exactly like `ghcr.io/owner/image`. Log in with a token read from a file into a variable, never printed, and never after `-p` (it would land in your shell history):
```bash
GITEA_TOKEN=$(cat "$LESSON/lab/.tokens/asha-cli")
echo "$GITEA_TOKEN" | docker login localhost:3000 -u asha --password-stdin
docker tag localhost:5001/allcsvideos/api:sha-$SHA localhost:3000/allcsvideos/api:1.4.2
docker push localhost:3000/allcsvideos/api:1.4.2
```
`Login Succeeded`, then seven layers pushed and the same digest as in the CI registry: a digest is the content, not the location. (Without a credential helper you also get `WARNING! Your credentials are stored unencrypted in '.../.docker/config.json'`. Hold that thought.)

Does Gitea protect `1.4.2`? Push Priya's build there too, then delete the bad version through the API:
```bash
docker tag localhost:5001/allcsvideos/api:1.4.2 localhost:3000/allcsvideos/api:1.4.2
docker push localhost:3000/allcsvideos/api:1.4.2
curl -s -o /dev/null -w "%{http_code}\n" -X DELETE -H "Authorization: token $GITEA_TOKEN" localhost:3000/api/v1/packages/allcsvideos/container/api/1.4.2
```
Accepted with the new digest (open http://localhost:3000/allcsvideos/-/packages to see it), then `204`. Gitea tags are mutable too. Deleting is a write permission, and it is final.

### 7. Promote, don't rebuild
Copy the tested image from the CI registry into Gitea, as `1.4.2` and `prod`. Registry to registry: nothing is built or pulled.
```bash
docker buildx imagetools create --tag localhost:3000/allcsvideos/api:1.4.2 --tag localhost:3000/allcsvideos/api:prod localhost:5001/allcsvideos/api:sha-$SHA
for r in localhost:5001/allcsvideos/api:sha-$SHA localhost:3000/allcsvideos/api:{1.4.2,prod}; do printf '%-44s' $r; docker buildx imagetools inspect --format '{{.Manifest.Digest}}' $r | cut -c1-23; done
curl -s -o /dev/null -w "%{http_code}\n" -X POST -H "Authorization: token $GITEA_TOKEN" localhost:3000/api/v1/packages/allcsvideos/container/api/-/link/allcsvideos-api
```
One digest for all three names, then `201`: the package page now links to the `allcsvideos-api` repository.

### 8. Pull-only credentials for servers
Play the production server: log in as `prod-deploy` (team `deployers`, packages: read, token scope `read:package`).
```bash
docker logout localhost:3000
DEPLOY_TOKEN=$(cat "$LESSON/lab/.tokens/prod-deploy-pull")
echo "$DEPLOY_TOKEN" | docker login localhost:3000 -u prod-deploy --password-stdin 2>/dev/null
docker pull localhost:3000/allcsvideos/api:prod
docker tag localhost:3000/allcsvideos/api:prod localhost:3000/allcsvideos/api:hotfix
docker push localhost:3000/allcsvideos/api:hotfix
```
The pull works (your tested digest). The push reads the layers (they exist) but writing the tag fails: `... manifests/hotfix: 401 Unauthorized`. A leaked server token cannot publish an image. Pushing belongs to CI, through its own account (`ci-bot`, team `ci`, write).

Where did Docker keep that token?
```bash
grep credsStore ~/.docker/config.json
jq '.auths[].auth |= .[0:6] + "...(hidden)"' ~/.docker/config.json
```
With Docker Desktop you will see `"credsStore": "desktop"`: the password sits in your OS keychain, not in the file. Without a credential helper (the video's lab terminal, many Linux servers) the file holds an `auth` value, and it is only base64:
```bash
jq -r '.auths["localhost:3000"].auth' ~/.docker/config.json | base64 -d | cut -d: -f1     # only without a helper: prints prod-deploy
```
Base64 is an encoding, not encryption. On servers: a credential helper, read-only tokens, rotation.

### 9. One tag, two platforms
A dedicated builder (docker-container driver, BuildKit pinned, host network so it reaches `localhost:5001`, plain HTTP allowed by `lab/buildkitd.toml`):
```bash
cat "$LESSON/lab/buildkitd.toml"
docker buildx create --name lab-builder --driver docker-container --driver-opt image=moby/buildkit:v0.30.0,network=host --buildkitd-config "$LESSON/lab/buildkitd.toml"
docker buildx inspect --bootstrap lab-builder | grep -E '^(Name|Driver|Status|Platforms|BuildKit version):'
docker buildx build --builder lab-builder --platform linux/amd64,linux/arm64 \
  --annotation "index:org.opencontainers.image.revision=$(git rev-parse HEAD)" \
  --annotation "index:org.opencontainers.image.version=1.4.2" \
  -t localhost:5001/allcsvideos/api:sha-$SHA-multiarch --push .
docker buildx imagetools inspect localhost:5001/allcsvideos/api:sha-$SHA-multiarch | grep -E '^(MediaType|Digest)|Platform'
docker buildx imagetools inspect --raw localhost:5001/allcsvideos/api:sha-$SHA-multiarch | jq .annotations
docker buildx rm lab-builder
```
If the push cannot reach `localhost:5001`, turn on host networking in Docker Desktop (Settings, Resources, Network) and recreate the builder. A separate test tag (`-multiarch`), because `sha-…` already names other bytes and must never change. You should see `application/vnd.oci.image.index.v1+json`, platforms `linux/amd64`, `linux/arm64` and two `unknown/unknown` (attestations), and the two annotations. Labels live inside each image's config; annotations sit on the index, so tools read them without pulling.

### 10. Retention
**Gitea cleanup rules.** First let "CI" push a `sha-` tag for every commit (as `ci-bot`):
```bash
bash "$LESSON/lab/ci-history.sh"
ADMIN_TOKEN=$(cat "$LESSON/lab/.tokens/asha-admin")
curl -s -H "Authorization: token $GITEA_TOKEN" "localhost:3000/api/v1/packages/allcsvideos?type=container" | jq -r ".[].version" | grep -v sha256
```
Five versions: three `sha-…`, `prod`, `1.4.2`. In the browser (signed in as asha): **allcsvideos organisation → Settings → Packages → Add cleanup rule**:
- Type: `container`, Enabled: on
- Keep the most recent: `1` version
- Keep versions matching: `prod|\d+\.\d+\.\d+`
- Remove versions older than: (leave empty / 0 days)
- Remove versions matching: `sha-.+`

Save, then open the rule's **Preview**: two packages scheduled for removal, the two older `sha-` tags (`latest` is always kept for container packages). The job normally runs at midnight; trigger it now:
```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST -H "Authorization: token $ADMIN_TOKEN" localhost:3000/api/v1/admin/cron/cleanup_packages
sleep 2; curl -s -H "Authorization: token $GITEA_TOKEN" "localhost:3000/api/v1/packages/allcsvideos?type=container" | jq -r ".[].version" | grep -v sha256
```
`204`, then only `sha-<release>`, `prod` and `1.4.2`.

**The CNCF registry: delete, then garbage-collect.** It has no rules, only an API and a garbage collector. Delete the multi-arch test image by its digest:
```bash
MULTI=$(docker buildx imagetools inspect --format '{{.Manifest.Digest}}' localhost:5001/allcsvideos/api:sha-$SHA-multiarch)
curl -s -o /dev/null -w '%{http_code}\n' -X DELETE localhost:5001/v2/allcsvideos/api/manifests/$MULTI
curl -s localhost:5001/v2/allcsvideos/api/tags/list
docker exec registry du -sh /var/lib/registry
```
`202`, the tag is gone, but nothing is freed on disk: blobs stay until garbage collection. Run it only while the registry is stopped (or read-only), or an upload in progress can lose layers:
```bash
docker stop registry
docker run --rm -v registry-data:/var/lib/registry registry:3.1.2 garbage-collect --delete-untagged /etc/distribution/config.yml 2>&1 | grep -E 'marked|^manifest eligible' | cut -c1-96
docker start registry
docker exec registry du -sh /var/lib/registry
```
In the video: `19 blobs marked, 32 blobs and 10 manifests eligible for deletion`, 39.1M down to 20.1M. Among them Friday's and Monday's untagged builds:
```bash
curl -s -o /dev/null -w '%{http_code}\n' -H 'Accept: application/vnd.oci.image.index.v1+json' localhost:5001/v2/allcsvideos/api/manifests/$FRIDAY
```
It no longer answers `200` (expect `404`): Friday's good build is gone for good. Untagged means garbage; anything you might roll back to needs a tag your rules keep.

### 11. The same on GHCR and ECR (reference, do not run here)
These come from the narration and the GitHub/AWS docs. ECR costs money and is done for real in Module 10.
```bash
# GHCR: images are ghcr.io/<namespace>/<image>. A classic personal access token needs
# read:packages to pull, write:packages to push, delete:packages to delete.
echo "$GHCR_TOKEN" | docker login ghcr.io -u <your-github-user> --password-stdin
# In GitHub Actions use GITHUB_TOKEN with   permissions: { packages: write }   (new packages are private by default).

# ECR login: the token is valid for 12 hours; IAM policies decide who may pull or push.
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin 123456789012.dkr.ecr.<region>.amazonaws.com
# Tag immutability, per repository: a push of an existing tag then fails with ImageTagAlreadyExistsException.
aws ecr put-image-tag-mutability --repository-name <repo> --image-tag-mutability IMMUTABLE
```
An ECR lifecycle policy is JSON rules with a priority, a selection and an action, for example "expire tagged images starting with `prod`, 14 days after push":
```json
{
  "rules": [{
    "rulePriority": 1,
    "description": "Expire prod images older than 14 days",
    "selection": { "tagStatus": "tagged", "tagPrefixList": ["prod"], "countType": "sinceImagePushed", "countUnit": "days", "countNumber": 14 },
    "action": { "type": "expire" }
  }]
}
```
Since July 2025 ECR immutability can have exclusion filters (everything immutable except, say, `latest`), and since November 2025 a lifecycle action can move old images to a cheaper archive storage class instead of deleting them.

## Common mistakes
- **Deploying `latest`.** You cannot tell what is running, two servers can run different images, and rollback pulls the same broken build. Deploy an exact version or a digest.
- **Rebuilding for production instead of promoting.** A rebuild is a new image nobody tested. Promote the tested digest with new tags.
- **Mutable release tags.** A re-push silently changed `1.4.2` in both registries. Turn on immutability where the registry has it, and make CI refuse to overwrite a release tag everywhere else.
- **Leaked registry credentials.** Tokens in `config.json`, in shell history (`-p`), or with push rights on every server. Use credential helpers, `--password-stdin`, read-only tokens for servers, push only from CI, short-lived tokens.
- **Unbounded registry growth.** Set cleanup rules or lifecycle policies, keep what you may roll back to, and garbage-collect (with the registry stopped).
- **Losing the digest.** Write down which digest is running; untagged builds are the first thing garbage collection removes.

## Clean up
```bash
docker logout localhost:3000
bash "$LESSON/lab/down.sh"             # prod, registry, gitea, the builder, volumes, tokens, ~/allcsvideos-api
docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^localhost:(5001|3000)/allcsvideos/api:' | xargs docker rmi
```
The pulled images `registry:3.1.2`, `gitea/gitea:28.1.0`, `moby/buildkit:v0.30.0` and `python:3.13.16-alpine3.23` stay in your cache; `docker rmi` them if you want the space back.

## Next
[M07-B01 · Containerise the allcsvideos Stack](../m07-b01-containerise-the-allcsvideos-stack/): the Module 7 build, where the whole platform comes together.
