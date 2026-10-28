# M18-B01 · A Secure Delivery Pipeline
> Video: Module 18, Build 1. Watch it first, then follow along here.

## What you'll learn
- Joining Module 18 into one path to production: four required gates on every pull request, then build once, scan the
  digest, SBOM, sign, attest, verify, and deploy by digest.
- Keeping the signing key only in the CI secret store, and giving the deploy job a token that can only change prod.
- Kyverno as the door: only images from our registry, signed by the pipeline's key, whoever sends them.
- Four staged breaks, all stopped: a laptop hotfix, a key in a pull request, a critical CVE, and a tampered tag.
- What changes at real scale: keyless signing, KMS keys, hardened provenance, Audit-then-Deny, exceptions, immutable tags.

## Before you start
- Docker Desktop with about 6 GB free memory, plus `bash`, `curl` and `jq`.
- All of Module 18: [L01](../m18-l01-shift-left/) gates, [L02](../m18-l02-secrets-management/) secrets,
  [L03](../m18-l03-supply-chain-security/) signing, [L04](../m18-l04-kubernetes-security/) Kyverno.
- Free port 3000 (Gitea).
- Pinned versions: `gitea/gitea:28.1.0`, `gitea/runner:5.1.1`, `gitea/runner-images:ubuntu-24.04-v26.10.01`,
  `docker:29.5.3-dind`, `registry:3.1.2`, `kindest/node:v1.35.8` (by digest), Kyverno chart 3.9.2 (1.19.2), kind v0.33.0,
  kubectl v1.35.9, helm v4.3.1, cosign v3.1.4, gitleaks 8.30.1, uv 0.13.4, Semgrep 1.182.0, Trivy 0.76.0, Syft 1.55.0,
  Checkov 3.3.30, `moby/buildkit:v0.30.0` (Priya's laptop builder).
- **Intel/AMD machine?** The pipeline was recorded on arm64. Set `PLATFORM: linux/amd64` at the top of
  `repo/.gitea/workflows/pipeline.yml` before step 4 (the kubectl step picks its architecture by itself).
- Every key, password and token here is **fake** or lab-only. The staged AWS key is a labelled fake.

## Files in this folder
| File | What it is |
|---|---|
| `lab/lab.sh` | `up` (Gitea, registry, CI Docker daemon, team machine, accounts, kind + Kyverno, runner, seeded repo), `shell NAME`, `protect`, `down` |
| `lab/image/Dockerfile` | The team machine: git, gitleaks, uv, kind, kubectl, helm, cosign, docker CLI (pinned, checksum-verified) |
| `lab/runner/config.yaml` | Runner config: jobs build on the CI Docker daemon (`docker:2376`), never on your laptop's Docker |
| `lab/gitea-secret` | Helper: stores stdin as a Gitea Actions secret (never prints it) |
| `lab/deployer-kubeconfig` | Helper: a kubeconfig with a 48-hour token for the prod `deployer` service account |
| `lab/laptop-buildkitd.toml`, `lab/kind-cluster.yaml` | Priya's laptop builder config (HTTP to the lab registry), the one-node cluster |
| `lab/ci.sh` | `runs`, `jobs RUN_ID`, `log JOB_ID`, `wait` |
| `repo/.gitea/workflows/pipeline.yml` | The pipeline: `secrets`, `sast`, `deps`, `iac` gates; `release` (main only); `deploy` |
| `repo/cluster/prod.yaml`, `repo/cluster/deployer.yaml` | The `prod` namespace (Pod Security restricted) and the deployer Role |
| `repo/cluster/policies/` | `only-our-registry` and `signed-by-pipeline` (you insert your public key) |
| `repo/cluster/kyverno-values.yaml` | Kyverno with only the admission controller (to fit a laptop) |
| `repo/deploy/copilot.yaml` | The prod Deployment and Service; `IMAGE_REF` is replaced by the digest |
| `repo/copilot/` | Course Copilot 1.7.0 (locked dependencies, base by digest) |
| `stages/` | The history the lab seeds (`s1`, `s2`), Priya's staged files (`s3`), the tamper image (`tamper/`) |

## Follow along
1. Start the lab (10+ minutes the first time).
   ```bash
   cd lab
   ./lab.sh up
   ```
   Open Gitea at http://localhost:3000 (`asha` / `fake-lab-pass-asha`; `rahul` and `priya` in `accounts.txt`).
   Shells: `./lab.sh shell asha`, `./lab.sh shell priya`, `./lab.sh shell rahul`.

2. **Step 2: the keys** (asha). A lab key pair with a fake password, stored only as Actions secrets.
   ```bash
   mkdir -p ~/keys && cd ~/keys
   export COSIGN_PASSWORD='FAKE-lab-only-m18b01'
   cosign generate-key-pair
   ls -l
   gitea-secret COSIGN_KEY < cosign.key
   printf %s "$COSIGN_PASSWORD" | gitea-secret COSIGN_PASSWORD
   curl -s -H "Authorization: token $(cat ~/.gitea-token)" http://gitea:3000/api/v1/repos/allcsvideos/allcsvideos-platform/actions/secrets | jq -r '.[].name'
   ```
   `COSIGN_KEY: HTTP 201`, `COSIGN_PASSWORD: HTTP 201`, and the list shows only names.

3. **Steps 1, 3 and 5: the pipeline, the cluster objects and the door** (asha). Put the new files on a branch, and your
   public key into the policy.
   ```bash
   cd ~/allcsvideos-platform
   git switch -q -c secure-delivery
   git rm -q .gitea/workflows/security.yml
   cp -r /lesson/repo/.gitea /lesson/repo/deploy /lesson/repo/cluster . && cp ~/keys/cosign.pub . && echo 1.8.0 > VERSION
   awk '/PIPELINE_PUBLIC_KEY/{while((getline l < "cosign.pub")>0) print "          " l; next} {print}' cluster/policies/signed-by-pipeline.yaml > /tmp/p && mv /tmp/p cluster/policies/signed-by-pipeline.yaml
   kubectl get nodes
   helm list -n kyverno
   kubectl get pods -n kyverno
   ```
   One node, Kyverno 3.9.2 / v1.19.2, only `kyverno-admission-controller`. (Edit `.gitea/workflows/pipeline.yml` now if
   you need `PLATFORM: linux/amd64`.)

4. **Step 4: prod and the deployer** (asha).
   ```bash
   kubectl apply -f cluster/prod.yaml -f cluster/deployer.yaml
   kubectl get ns prod --show-labels
   kubectl auth can-i patch deployments -n prod --as=system:serviceaccount:prod:deployer
   kubectl auth can-i get secrets -n prod --as=system:serviceaccount:prod:deployer
   kubectl auth can-i patch deployments -n kyverno --as=system:serviceaccount:prod:deployer
   ```
   `pod-security.kubernetes.io/enforce=restricted`, then `yes`, `no`, `no`.

5. **Step 5: the door.**
   ```bash
   kubectl apply -f cluster/policies/
   kubectl get validatingpolicies,imagevalidatingpolicies
   ```
   Both `READY true`. Kyverno checks the **signature**; the pipeline checks the SBOM attestation (Kyverno 1.19.2 requires
   a transparency-log proof for attestations, and this offline lab has no log).

6. **Step 6: the deploy credential and branch protection.**
   ```bash
   deployer-kubeconfig | gitea-secret KUBE_CONFIG
   ```
   `KUBE_CONFIG: HTTP 201`. Then on your laptop, in `lab/`: `./lab.sh protect` (`protect main: HTTP 201`).

7. **Run it** (asha).
   ```bash
   git status --short
   git add -A
   git commit -q -m 'pipeline: release, sign and deploy (copilot 1.8.0)'
   git push -q -u origin secure-delivery
   ```
   Open a pull request from `secure-delivery` to `main` in Gitea. The four gates run and turn green, each marked
   Required; `release` and `deploy` are skipped on a pull request. Log in as `rahul` and merge it. The run on main
   does the gates again, then `release` (build, image scan, SBOM, sign, attest, verify twice, SBOM artifact) and
   `deploy`. Follow it in the Gitea UI or with `./ci.sh runs` on your laptop.

8. **Prove it** (asha).
   ```bash
   git switch -q main && git pull -q
   DIGEST=$(kubectl get deploy copilot -n prod -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d@ -f2)
   kubectl get pods -n prod
   kubectl get deploy copilot -n prod -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
   kubectl get --raw /api/v1/namespaces/prod/services/copilot:80/proxy/health; echo
   IMAGE=registry.lab:5000/allcs/copilot
   cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry $IMAGE@$DIGEST > /dev/null; echo "exit code: $?"
   cosign verify-attestation --key cosign.pub --insecure-ignore-tlog --allow-http-registry --type cyclonedx $IMAGE@$DIGEST > att.json 2>/dev/null; echo "exit code: $?"
   jq '.payload | @base64d | fromjson | {predicateType, subject: .subject[0].digest.sha256[0:12], components: (.predicate.components | length)}' att.json
   curl -s http://registry.lab:5000/v2/allcs/copilot/tags/list | jq -r '.tags[]'
   ```
   ```
   registry.lab:5000/allcs/copilot@sha256:7d98c7aea46f...
   {"status":"ok","version":"1.8.0","courses":5}
   exit code: 0
   exit code: 0
   "predicateType": "https://cyclonedx.org/bom", "components": 2801
   1.8.0
   sha256-7d98c7...att
   sha256-7d98c7...sig
   ```

### The breaks (all staged)
9. **Break 1: the laptop hotfix** (priya). Her own builder, her own push, her admin kubeconfig.
   ```bash
   docker buildx create --name securepipe-laptop --driver docker-container --driver-opt network=securepipe-net,image=moby/buildkit:v0.30.0 --buildkitd-config /etc/laptop-buildkitd.toml --use --bootstrap
   cd ~ && git clone -q http://gitea:3000/allcsvideos/allcsvideos-platform.git && cd allcsvideos-platform
   git switch -q -c priya/thumbnails-webp
   cp /lesson/stages/s3/thumbnails-key.py copilot/app/thumbnails.py && echo 1.8.1 > VERSION
   git diff --stat
   docker buildx build -q --push -t registry.lab:5000/allcs/copilot:1.8.1-hotfix copilot
   kubectl -n prod set image deploy/copilot copilot=registry.lab:5000/allcs/copilot:1.8.1-hotfix
   kubectl -n prod set image deploy/copilot copilot=nginxinc/nginx-unprivileged:1.29.8-alpine
   kubectl get pods -n prod
   cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry registry.lab:5000/allcs/copilot:1.8.1-hotfix > /dev/null; echo "exit code: $?"
   ```
   ```
   denied the request: Policy signed-by-pipeline failed: image must be signed by the pipeline key
   denied the request: Policy only-our-registry failed: prod runs images from registry.lab:5000/allcs only
   Error: no signatures found
   exit code: 10
   ```
   Admission checks the object, not who sent it. The 1.8.0 pod keeps running.

10. **Break 2: a key in a pull request** (priya, same branch). The hook isn't on in this fresh clone.
    ```bash
    git diff copilot/app/thumbnails.py
    git commit -qam 'thumbnails: WebP with the right content type (1.8.1)'
    git push -q -u origin priya/thumbnails-webp
    ```
    Open the pull request in Gitea. `secrets` fails: `RuleID: aws-access-token`, `thumbnails.py`, line 8, redacted.
    Merging is blocked in the UI, and through the API too (`{"message":"Not all required status checks successful"}`,
    HTTP 405). The key never reached main, so rewrite the branch:
    ```bash
    cp /lesson/stages/s3/thumbnails-fixed.py copilot/app/thumbnails.py
    git config core.hooksPath .githooks
    git diff --stat
    git commit -a --amend --no-edit
    gitleaks git --redact --no-banner . ; echo "exit code: $?"
    git push -q --force-with-lease
    gitleaks git --redact --no-banner . ; echo "exit code: $?"
    ```
    The hook says `no leaks found`; the full scan still finds 1 until the force push moves `origin/priya/thumbnails-webp`,
    then `exit code: 0`. (A real key that reached the server is revoked and rotated anyway.) The gates go green; log in as
    `rahul` and merge: 1.8.1 is released and deployed, and `health` says `1.8.1`.

11. **Break 3: a vulnerable dependency** (rahul).
    ```bash
    cd ~ && git clone -q http://gitea:3000/allcsvideos/allcsvideos-platform.git && cd allcsvideos-platform && git config core.hooksPath .githooks
    cd copilot && git switch -q -c rahul/legacy-catalog
    sed -i 's/^pyyaml>=6.0/pyyaml==5.3.1/' requirements.in
    grep pyyaml requirements.in
    uv pip compile requirements.in --generate-hashes --python-version 3.13 -o requirements.txt -q
    git diff --stat
    git commit -qam 'catalog: pin pyyaml 5.3.1 for the legacy catalog importer'
    git push -q -u origin rahul/legacy-catalog
    ```
    Open the pull request: `deps` fails on `CVE-2020-14343` (PyYAML, CRITICAL, fixed in 5.4). The fix:
    ```bash
    git revert --no-edit HEAD | head -1
    grep pyyaml requirements.in
    git push -q
    ```
    `pyyaml>=6.0`, the gates go green, and Rahul closes the pull request.

12. **Break 4: a tampered tag** (priya builds, asha deploys).
    ```bash
    # priya
    cp -r /lesson/stages/tamper ~/tamper && cd ~/tamper
    cat Dockerfile
    docker buildx build -q --push -t registry.lab:5000/allcs/copilot:1.8.1 .
    ```
    ```bash
    # asha
    cd ~/allcsvideos-platform && git pull -q
    IMAGE=registry.lab:5000/allcs/copilot
    kubectl -n prod set image deploy/copilot copilot=$IMAGE:1.8.1
    cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry $IMAGE:1.8.1 > /dev/null 2>&1; echo "by tag: exit code $?"
    DIGEST=$(kubectl get deploy copilot -n prod -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d@ -f2)
    cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry $IMAGE@$DIGEST > /dev/null 2>&1; echo "by digest: exit code $?"
    kubectl get --raw /api/v1/namespaces/prod/services/copilot:80/proxy/health; echo
    ```
    Denied (the tag now resolves to an unsigned digest), `by tag: exit code 10`, `by digest: exit code 0`, and prod still
    serves the real 1.8.1. The remaining fix belongs to the registry: immutable tags, push rights for the pipeline only.

## Key ideas: at real scale
- **Keyless signing**: the CI job's OIDC token, a 10-minute Fulcio certificate, the Rekor log (GitHub: `permissions:
  id-token: write`; GitLab: `id_tokens` with audience `sigstore`, read from `SIGSTORE_ID_TOKEN`). The Kyverno attestor
  then names the issuer and the workflow identity, and can require the attestation too.
- **Keys in a KMS** if you keep keys: `awskms://`, `gcpkms://`, `azurekms://`, `hashivault://`.
- **Provenance from a hardened builder**: GitHub artifact attestations (SLSA Build L2, L3 with a shared reusable
  workflow), checked with `gh attestation verify`.
- **Audit first, then Deny**, and an exception process (Kyverno `PolicyException` has no expiry: keep them in Git with
  an owner and a date).
- **The registry**: authentication, pipeline-only push rights, immutable tags (Amazon ECR, Harbor).

## Common mistakes
- **Deploying by tag.** The pipeline deploys digests; the door checks signatures.
- **Trusting who sends the request.** Priya had admin rights and was still denied: admission checks the object.
- **Adding a fix commit on top of a leaked key.** If it never reached main, rewrite the branch (`--amend`,
  `--force-with-lease`); if it reached the server, revoke and rotate it too.
- **Long-lived signing keys in CI.** Prefer keyless signing or a KMS key.

## Clean up
On your laptop, in `lab/`:
```bash
./lab.sh down
```

## Next
[M19-L01 · Internal Developer Platforms](../../platform/m19-l01-internal-developer-platforms/)
