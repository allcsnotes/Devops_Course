# M19-L01 · Internal Developer Platforms
> Video: Module 19, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- Why platform teams exist: cognitive load (germane, intrinsic, extraneous) and the Team Topologies team types and interaction modes (stream-aligned team, platform team, X-as-a-Service)
- What an internal developer platform is (the CNCF Platforms white paper): capabilities, interfaces, and a portal on top that is only the front door
- Golden paths ("paved, not forced"), self-service, the thinnest viable platform and the CNCF platform engineering maturity model
- Backstage for real: the Software Catalog from `catalog-info.yaml` files, and a Software Template that creates a repo, a green CI pipeline and a catalog entry in one step
- How to measure a platform: lead time for a new service, adoption, DORA metrics and developer surveys

## Before you start
- Docker Desktop with at least **6 GB** of memory for its VM (the Backstage docs ask for 6 GB; the build runs in a container)
- Git, `curl` and `jq` on your laptop
- Versions the video used: Node **22.23.3** (in the `node:22.23.3` container, nothing to install), `@backstage/create-app` **0.9.3** (Backstage **1.56.0**, Yarn **4.13**), Gitea **28.1.0**, Gitea runner **5.1.1**
- This lab reuses the Gitea + Gitea Actions setup from Module 8 (CI) and the `allcsvideos/` folder at the root of this course repo. It does not change that folder: `seed.sh` works on a temporary copy.
- Every password and token in this lab is fake and lab-only.

## Files in this folder
| File | What it is |
| --- | --- |
| `lab/up.sh` | Network `idp-net` and Gitea 28.1.0 (Git, web UI, API, Gitea Actions) on http://gitea:3000 |
| `lab/forge.sh` | Lab accounts asha, priya, backstage-bot (fake passwords), tokens in `lab/secrets/`, org `allcsvideos`, team `devs` |
| `lab/seed.sh` | Pushes `allcsvideos/allcsvideos-platform` (the app + catalog files) and `allcsvideos/golden-paths` |
| `lab/runner.sh`, `lab/runner-config.yaml` | One Gitea Actions runner (gitea/runner:5.1.1), jobs on `idp-net` |
| `lab/backstage.sh` | Runs the portal image `allcsvideos-portal:1.0` on http://backstage:7007 |
| `lab/down.sh` | Removes everything the lab created |
| `portal/app-config.lab.yaml` | The portal's lab config: catalog locations in Gitea, the Gitea integration, guest sign-in as priya |
| `portal/packages/backend/src/index.ts` | The generated backend with one added line: the Gitea scaffolder module |
| `portal/packages/backend/Dockerfile.lab` | The generated backend Dockerfile with one change: `FROM node:22.23.3-slim` |
| `changes/` | Catalog descriptors added to the allcsvideos app (paths mirror `allcsvideos/`): the root Location, `catalog/org.yaml` (groups and users), `catalog/system.yaml` (system and resources), and one `catalog-info.yaml` per component |
| `golden-paths/python-service/template.yaml` | The Software Template "New Python service" (fixed version, see step 8) |
| `golden-paths/python-service/skeleton/` | What every new service gets: app, tests, non-root Dockerfile, CI workflow (3 jobs), Helm chart, Argo CD Application, `catalog-info.yaml` |

## Follow along

### 1. Name the lab hosts
Backstage, Gitea, your browser and git must all use the same URLs (`http://gitea:3000`, `http://backstage:7007`). Add one line to your hosts file (`/etc/hosts` on macOS/Linux, `C:\Windows\System32\drivers\etc\hosts` on Windows, as administrator):
```
127.0.0.1 gitea backstage
```
Remove it again when you finish the lesson.

### 2. Generate the Backstage app (Node 22.23.3 container)
Work in a folder outside this course repo, for example `~/idp-lab`. Start a Node 22.23.3 container with that folder mounted:
```bash
mkdir -p ~/idp-lab && cd ~/idp-lab
docker run --rm -it --name portal-build -v "$PWD":/work -w /work node:22.23.3 bash
```
Inside the container, the one scaffold command from the video:
```bash
npx @backstage/create-app@0.9.3
```
Answer `y` to install it, and enter the name `allcsvideos-portal`. You should see:
```
  Node version is: 22.23.3
? Enter a name for the app [required] allcsvideos-portal
...
  executing     yarn install ✔
  executing     yarn tsc ✔

🥇  Successfully created allcsvideos-portal
```
It takes a few minutes (under three in the video). `backstage.json` says `"version": "1.56.0"`.

### 3. Add the Gitea scaffolder module
The template publishes to Gitea, so the backend needs the Gitea module. Still inside the container:
```bash
cd allcsvideos-portal
yarn workspace backend add @backstage/plugin-scaffolder-backend-module-gitea
```
Then copy this folder's `portal/packages/backend/src/index.ts` over `packages/backend/src/index.ts` (from your laptop, or add the line yourself next to the GitHub module):
```ts
backend.add(import('@backstage/plugin-scaffolder-backend-module-gitea'));
```

### 4. Production build and image
Still inside the container:
```bash
export NODE_OPTIONS=--max-old-space-size=3072 && time (yarn tsc && yarn build:backend)
exit
```
You should see the app bundled into the backend, ending with:
```
Moving backend into dist workspace
Moving app into dist workspace

real    0m18.203s
```
Back on your laptop, copy in the lab files and build the image (from `~/idp-lab/allcsvideos-portal`; replace `<course-repo>` with where you cloned this repo):
```bash
cd ~/idp-lab/allcsvideos-portal
cp <course-repo>/platform/m19-l01-internal-developer-platforms/portal/app-config.lab.yaml .
cp <course-repo>/platform/m19-l01-internal-developer-platforms/portal/packages/backend/Dockerfile.lab packages/backend/
docker build -f packages/backend/Dockerfile.lab -t allcsvideos-portal:1.0 .
```
The only change from the generated `Dockerfile`: the same Node version as the build (`node:22.23.3-slim` instead of `node:24-trixie-slim`), because the generated file warns that mismatched versions break native modules. The image is about 1.22 GB, built once.

### 5. Start Gitea, accounts, repositories and the runner
From this lesson folder:
```bash
./lab/up.sh
./lab/forge.sh
./lab/seed.sh
./lab/runner.sh
```
`seed.sh` prints the two repositories it created: `allcsvideos/allcsvideos-platform` and `allcsvideos/golden-paths`. Open http://gitea:3000 to look around (sign in as `asha` / `fake-lab-pass-asha` if you like).

### 6. Read the lab config, then start Backstage
Open `portal/app-config.lab.yaml`:
- `catalog.locations`: two `url` locations in the lab's Gitea, the platform repo's root `catalog-info.yaml` and the golden path's `template.yaml`
- `integrations.gitea`: the `backstage-bot` account; its token comes from `${GITEA_TOKEN}`, read from a mounted file
- `auth.providers.guest`: guest sign-in mapped to `user:default/priya`, with `dangerouslyAllowOutsideDevelopment: true`. **Lab only.** A real portal signs in through your company's identity provider.

```bash
./lab/backstage.sh
```
You should see `backstage up after ...`. Open http://backstage:7007 and click **Enter** (guest).

### 7. The Software Catalog
Look at `changes/api/catalog-service/catalog-info.yaml`: a `Component` (service, production, owner `group:courses`, system `allcsvideos`, provides `catalog-api`, depends on `resource:catalog-db` and `resource:cache`) and an `API` of type `openapi` with `/courses` and `/courses/{id}`. Teams and people are in `changes/catalog/org.yaml`, and `changes/catalog-info.yaml` is the one Location that lists them all.

In Backstage:
- **Catalog**: Priya is signed in, so "Owned" shows her team's three components (catalog-service, storefront, course-copilot)
- open **catalog-service**: owner, system, lifecycle, the API it provides, the resources it depends on, and the relations graph
- open the **allcsvideos** system: four components, two resources, one API, one owner

### 8. The golden path: a Software Template
Read `golden-paths/python-service/template.yaml`:
- `kind: Template`, owner `group:platform`
- `parameters` become a form: page one (name, description, owner picked from the catalog's groups), page two (repository, only `gitea:3000` and only the `allcsvideos` organisation)
- three `steps`: `fetch:template` (copies `./skeleton` and fills in the values), `publish:gitea` (creates the repo and pushes the first commit), `catalog:register` (adds the new component to the catalog)

The video's first real run failed at the register step with **400 Bad Request**: the URL in the log was missing the branch (`.../src/branch/catalog-info.yaml`), because with Gitea `repoContentsUrl` plus `catalogInfoPath` lost it. The file here is already fixed (two lines out, one line in):
```diff
-        repoContentsUrl: ${{ steps['publish'].output.repoContentsUrl }}
-        catalogInfoPath: /catalog-info.yaml
+        catalogInfoUrl: ${{ steps['publish'].output.repoContentsUrl }}catalog-info.yaml
```
A template is software: test it before teams depend on it.

### 9. Priya creates `certificates`
In Backstage: **Create** -> **New Python service** -> Choose.
1. Name `certificates`, Description `Course completion certificates for students`, Owner **Courses team** -> Next
2. Repository: host `gitea:3000`, owner `allcsvideos`, repository `certificates` -> Review -> **Create**

You should see three green steps (Fetch the skeleton, Create the repository, Register in the catalog) and two links: **Repository** and **Open in catalog**. The register step logs:
```
Registering http://gitea:3000/allcsvideos/certificates/src/branch/main/catalog-info.yaml in the catalog
```
In Gitea, `allcsvideos/certificates` has one commit by the scaffolder, and the push started the first pipeline by itself: three jobs, `test`, `dockerfile`, `chart`, all green (3 seconds in the video). The job logs show:
```
Ran 3 tests in 0.000s

OK
```
```
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```
and hadolint prints nothing (no findings).

### 10. Clone it like Priya
```bash
cd ~/idp-lab
git clone -q http://gitea:3000/allcsvideos/certificates.git && cd certificates
git log --oneline
tree -a -I .git
python3 -m unittest -v
```
You should see one commit (`initial commit`), `8 directories, 13 files`, and:
```
test_health (tests.test_main.TestHandle.test_health) ... ok
test_root_names_the_service (tests.test_main.TestHandle.test_root_names_the_service) ... ok
test_unknown_path (tests.test_main.TestHandle.test_unknown_path) ... ok
```
Also look at `catalog-info.yaml` (owner `group:default/courses`, lifecycle `experimental`, a "CI runs" link), `deploy/chart/values.yaml` (platform defaults: 2 replicas, requests 50m / 64Mi, limit 128Mi) and `.gitea/workflows/ci.yaml`. Back in the catalog, `certificates` shows up owned by the Courses team. Nobody filed a ticket.

Note: `deploy/argocd-app.yaml` is for the Module 15 GitOps setup. Nothing deploys it in this lab: there is no cluster here.

### 11. Measure it
In the video: Create was clicked at 23:42:33 and the pipeline finished green at 23:42:42, about **9 seconds**, against an illustrated two weeks of tickets. Be fair to the numbers: the template covers five of the eight tickets (repository, pipeline, Dockerfile, Helm chart, Argo CD app) plus a catalog entry; secrets, dashboards and alerts are still tickets, the platform's roadmap. Then track adoption, DORA metrics per team, and a quarterly developer survey.

## Common mistakes
- **Building a portal nobody asked for.** Interview the teams first, and fix the wait that hurts them most.
- **Mandating the platform.** A forced path hides what is wrong with it. Make it the easiest way and let adoption tell you the truth.
- **Ticket-ops behind a nice UI.** If the Create button opens a ticket for a human, nothing got faster.
- **Too many abstractions.** Teams must still be able to debug their own service at 2 a.m. Keep the YAML readable.
- **Untested templates.** The first real run here failed (400 Bad Request at `catalog:register`); see step 8.
- Lab-specific: forgetting the hosts entry (step 1), so `http://gitea:3000` or `http://backstage:7007` does not open; building the image with a different Node version than the `yarn build:backend` step.

## Clean up
```bash
./lab/down.sh
rm -rf ~/idp-lab
```
Then remove the `127.0.0.1 gitea backstage` line from your hosts file. Optionally remove the pulled images: `docker rmi gitea/gitea:28.1.0 gitea/runner:5.1.1 gitea/runner-images:ubuntu-24.04-v26.10.01 node:22.23.3 node:22.23.3-slim hadolint/hadolint:v2.15.1 alpine/helm:4.3.1`.

## Next
[M19-L02 · FinOps](../m19-l02-finops/)
