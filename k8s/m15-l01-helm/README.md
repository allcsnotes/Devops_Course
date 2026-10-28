# M15-L01 · Helm
> Video: Module 15, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- Why copying the same manifests per environment leads to drift, and how Helm fixes it (Helm is "apt for Kubernetes").
- How one `helm install` works: chart + values -> Go templates -> plain YAML -> applied -> a release revision stored as a Secret.
- Installing a public chart from an OCI registry, writing your own chart (`_helpers.tpl`, `required`, `values.schema.json`).
- One chart, two environments with small values files, and `helm upgrade --install`.
- Safe upgrades: `helm diff`, `helm rollback`, `--rollback-on-failure`, a pre-upgrade hook, packaging to OCI, dependencies.
- The five pitfalls: secrets in values, `--reuse-values`, editing release objects by hand, giant templates, floating versions.

## Before you start
- Docker Desktop, plus these tools on your laptop (the video used exactly these versions):
  - `kind` v0.33.0, `kubectl` v1.37.x, `helm` v4.3.1 (Helm 4 - the flags in this lesson are Helm 4 flags)
  - `jq`, `curl`, `patch`, and optionally `tree`
- Kubernetes basics from Module 13 and the `helm install` you typed in Module 14.

## Files in this folder
| File | What it is |
|---|---|
| `lab/up.sh` | Creates the kind cluster `helm-lab` (Kubernetes 1.37), a local OCI registry on `127.0.0.1:5001`, builds and loads `allcsvideos/api:2.4.0` and `:2.5.0` |
| `lab/down.sh` | Deletes everything `up.sh` created |
| `lab/kind-cluster.yaml` | The one-node kind cluster config |
| `app/` | The small catalog API (Python, standard library) used as the app being deployed |
| `workspace/k8s/staging/`, `workspace/k8s/prod/` | The "before Helm" picture: 12 manifests copied per environment, already drifted |
| `workspace/podinfo-values.yaml` | Your settings for the public podinfo chart (only what differs from its defaults) |
| `workspace/charts/allcsvideos-api/` | Our own chart: `Chart.yaml`, `values.yaml`, `values.schema.json`, 7 templates |
| `workspace/env/values-staging.yaml`, `values-prod.yaml` | Only the differences per environment |
| `workspace/charts/allcsvideos/` | Umbrella chart with two dependencies (our API chart + podinfo as `status-page`) |
| `chart-0.2.0.patch` | The chart 0.2.0 change used in the `--reuse-values` pitfall |

## Follow along

1. Start the lab and make a working copy of the workspace (you will edit files in it):
   ```bash
   LESSON=$PWD                       # run this from this lesson's folder
   bash lab/up.sh
   cp -R workspace ~/allcsvideos-helm
   cd ~/allcsvideos-helm
   ```

2. The problem: the same manifests copied per environment.
   ```bash
   tree k8s
   diff -rq k8s/staging k8s/prod | wc -l
   diff k8s/staging/api-deployment.yaml k8s/prod/api-deployment.yaml
   ```
   You should see `24 files`, `8` differing pairs, and in the Deployment diff the expected changes (replicas, tag,
   resources) plus one that is not: the `readinessProbe` exists only in staging. That is copy-paste drift.

3. Check the lab:
   ```bash
   kubectl get nodes
   helm version --short
   kubectl get ns
   ```
   ```
   NAME                     STATUS   ROLES           AGE   VERSION
   helm-lab-control-plane   Ready    control-plane   ...   v1.37.0
   v4.3.1+gc0d08d0
   ```

4. Someone else's chart: search Artifact Hub, read the chart and its values from the OCI registry.
   ```bash
   helm search hub podinfo --max-col-width 60
   helm show chart oci://ghcr.io/stefanprodan/charts/podinfo --version 6.15.0
   helm show values oci://ghcr.io/stefanprodan/charts/podinfo --version 6.15.0 | wc -l
   helm show values oci://ghcr.io/stefanprodan/charts/podinfo --version 6.15.0 | head -20
   cat podinfo-values.yaml
   ```
   The chart is `version: 6.15.0`; its values file is about 309 lines. Write only what you change.

5. Install it as release `demo`:
   ```bash
   helm install demo oci://ghcr.io/stefanprodan/charts/podinfo --version 6.15.0 -n demo --create-namespace \
     --set replicaCount=2 -f podinfo-values.yaml
   kubectl -n demo rollout status deploy/demo-podinfo --timeout=180s
   kubectl -n demo get pods
   helm list -A
   ```
   ```
   STATUS: deployed
   REVISION: 1
   ...
   NAME	NAMESPACE	REVISION	...	STATUS  	CHART         	APP VERSION
   demo	demo     	1       	...	deployed	podinfo-6.15.0	6.15.0
   ```

6. What Helm applied, and the app answering:
   ```bash
   helm get values demo -n demo
   helm get manifest demo -n demo | grep -E "^kind:|replicas:|PODINFO_UI|image:"
   kubectl -n demo port-forward svc/demo-podinfo 9898:9898 >/dev/null & sleep 3
   curl -s localhost:9898 | jq "{hostname, message, color, version}"
   kill %1; wait
   ```
   You should see `"message": "Hello from allcsvideos"` and `"color": "#1a7cff"`.

7. The release is just a Secret. Decode it (base64 twice, then gunzip):
   ```bash
   kubectl -n demo get secrets
   kubectl -n demo get secret sh.helm.release.v1.demo.v1 -o jsonpath="{.data.release}" \
     | base64 -d | base64 -d | gzip -d | jq "{name, version, namespace, status: .info.status, chart: .chart.metadata.version}"
   ```
   ```
   sh.helm.release.v1.demo.v1   helm.sh/release.v1   1   ...
   { "name": "demo", "version": 1, "namespace": "demo", "status": "deployed", "chart": "6.15.0" }
   ```
   (On macOS, if `base64 -d` complains, use `base64 -D`.)

8. Your own chart. Look at the starter chart, then at ours:
   ```bash
   helm create scratch
   tree scratch
   rm -rf scratch
   tree charts/allcsvideos-api
   cat charts/allcsvideos-api/Chart.yaml
   ```
   Open `charts/allcsvideos-api/templates/deployment.yaml` and `_helpers.tpl` and find `include "api.fullname"`,
   `nindent`, `default .Chart.AppVersion`, `toYaml` and the `checksum/config` annotation.

9. Render locally, lint, and let the chart stop bad values:
   ```bash
   helm template api charts/allcsvideos-api -f env/values-prod.yaml -s templates/deployment.yaml
   helm lint charts/allcsvideos-api -f env/values-prod.yaml
   helm template api charts/allcsvideos-api --set ingress.enabled=true
   helm template api charts/allcsvideos-api --set replicaCount=0
   helm template api charts/allcsvideos-api --set image.tag=latest
   ```
   ```
   [INFO] Chart.yaml: icon is recommended
   1 chart(s) linted, 0 chart(s) failed
   Error: execution error at (allcsvideos-api/templates/ingress.yaml:11:13): ingress.host is required when ingress.enabled is true
   - at '/replicaCount': minimum: got 0, want 1
   - at '/image/tag': 'latest' does not match pattern '^$|^[0-9]+\\.[0-9]+\\.[0-9]+$'
   ```

10. A Helm dry run is not validation; the API server's dry run is:
    ```bash
    helm install api charts/allcsvideos-api -n prod --set resources.limits.memory=lots --dry-run=server \
      | grep -E "STATUS|DESCRIPTION|memory: lots"
    helm template api charts/allcsvideos-api --set resources.limits.memory=lots | kubectl apply --dry-run=server -f -
    ```
    Helm says `Dry run complete`; `kubectl apply --dry-run=server` says `quantities must match the regular expression`.

11. One chart, two environments:
    ```bash
    helm upgrade --install api charts/allcsvideos-api -n staging --create-namespace -f env/values-staging.yaml --wait --timeout 5m
    helm upgrade --install api charts/allcsvideos-api -n prod --create-namespace -f env/values-prod.yaml --wait --timeout 5m
    helm list -A
    kubectl get deploy,ingress -A -l app.kubernetes.io/instance=api
    ```
    Staging runs `1/1`, prod `3/3`. Ingress ADDRESS is empty: this lab has no ingress controller.

12. Ask both environments which version they run:
    ```bash
    kubectl -n staging port-forward svc/api 8081:80 >/dev/null & kubectl -n prod port-forward svc/api 8082:80 >/dev/null & sleep 3
    curl -s localhost:8081/courses | jq -c "{version, pod}"; curl -s localhost:8082/courses | jq -c "{version, pod}"
    kill %1 %2; wait
    ```
    ```
    {"version":"2.5.0","pod":"api-..."}
    {"version":"2.4.0","pod":"api-..."}
    ```

13. Run the same prod command again: a new revision, but no new pods (same ReplicaSet hash).
    ```bash
    kubectl -n prod get rs
    helm upgrade --install api charts/allcsvideos-api -n prod -f env/values-prod.yaml --wait --timeout 5m | head -6
    kubectl -n prod get rs
    helm history api -n prod
    ```

14. Install the signed helm-diff plugin. Helm 4 verifies plugin signatures. Pick the file for your OS/CPU from the
    [v3.15.15 release page](https://github.com/databus23/helm-diff/releases/tag/v3.15.15) (the video used `linux-arm64`):
    ```bash
    curl -fsSLO https://github.com/databus23/helm-diff/releases/download/v3.15.15/pubkey.asc
    helm plugin install https://github.com/databus23/helm-diff/releases/download/v3.15.15/diff-3.15.15-linux-arm64.tgz \
      --keyring pubkey.asc
    helm plugin list
    ```
    You should see `Verifying plugin signature...`, `Plugin Hash Verified`, and `diff  3.15.15`.

15. Preview, then upgrade production to 2.5.0:
    ```bash
    sed -i.bak 's/tag: "2.4.0"/tag: "2.5.0"/' env/values-prod.yaml && rm env/values-prod.yaml.bak
    grep tag env/values-prod.yaml
    helm diff upgrade api charts/allcsvideos-api -n prod -f env/values-prod.yaml --context 1
    helm upgrade api charts/allcsvideos-api -n prod -f env/values-prod.yaml --wait --timeout 5m | head -6
    helm history api -n prod
    ```
    The diff shows the version label on all four objects, a new `checksum/config`, and the image `2.4.0` -> `2.5.0`.
    The upgrade is `REVISION: 3`.

16. Break it on purpose (tag 2.6.0 was never built), then roll back:
    ```bash
    helm upgrade api charts/allcsvideos-api -n prod -f env/values-prod.yaml --set image.tag=2.6.0 --wait --timeout 60s
    kubectl -n prod get pods
    helm history api -n prod
    helm rollback api 3 -n prod --wait --timeout 5m
    kubectl -n prod get pods
    helm history api -n prod
    ```
    ```
    Error: UPGRADE FAILED: resource Deployment/prod/api not ready. status: InProgress, message: Updated: 1/3
    api-5d8677788f-mj9t2   0/1     ErrImagePull   0   ...
    4   ...   failed     ...
    5   ...   deployed   ...   Rollback to 3
    ```
    The three good pods keep serving the whole time.

17. Let Helm roll back by itself:
    ```bash
    helm upgrade api charts/allcsvideos-api -n prod -f env/values-prod.yaml --set image.tag=2.6.0 \
      --rollback-on-failure --timeout 60s
    helm history api -n prod
    kubectl -n prod get deploy api -o jsonpath="{.spec.template.spec.containers[0].image}{\"\n\"}"
    ```
    You should see `has been rolled back due to rollback-on-failure being set`, revision 6 `failed`, 7 `Rollback to 5`,
    and the image back on `allcsvideos/api:2.5.0`.

18. A pre-upgrade hook runs the database migration Job first:
    ```bash
    helm upgrade api charts/allcsvideos-api -n staging -f env/values-staging.yaml --set migration.enabled=true \
      --wait --timeout 5m | head -6
    kubectl -n staging get job,pod -l app.kubernetes.io/instance=api
    kubectl -n staging logs job/api-migrate
    ```
    ```
    job.batch/api-migrate   Complete   1/1
    migrating catalog schema for 2.5.0 ... done
    ```

19. Package the chart and push it to the local OCI registry:
    ```bash
    helm package charts/allcsvideos-api
    helm push allcsvideos-api-0.1.0.tgz oci://localhost:5001/charts --plain-http
    curl -s localhost:5001/v2/charts/allcsvideos-api/tags/list
    helm show chart oci://localhost:5001/charts/allcsvideos-api --version 0.1.0 --plain-http
    helm pull oci://localhost:5001/charts/allcsvideos-api --version 0.1.0 --plain-http -d /tmp
    ls -l /tmp/*.tgz
    ```
    ```
    {"name":"charts/allcsvideos-api","tags":["0.1.0"]}
    ```

20. Dependencies: the umbrella chart.
    ```bash
    cat charts/allcsvideos/Chart.yaml
    helm dependency update charts/allcsvideos
    tree charts/allcsvideos
    helm template platform charts/allcsvideos | grep -E "^# Source: .*deployment|replicas:"
    ```
    `Chart.lock` and `charts/*.tgz` appear; the API renders with `replicas: 2`, the status page with `replicas: 1`.

21. Pitfall 1 - secrets in values (`demo-password-123` is a fake teaching value):
    ```bash
    helm upgrade api charts/allcsvideos-api -n staging -f env/values-staging.yaml \
      --set config.databaseUrl=postgres://api:demo-password-123@db.allcsvideos.internal:5432/catalog | head -3
    helm get values api -n staging
    kubectl -n staging get secrets
    ```
    The password comes right back, and it is stored in every `sh.helm.release.v1.api.vN` Secret.

22. Pitfall 2 - `--reuse-values`. Apply chart 0.2.0 (adds `cacheTtlSeconds: 300`), then compare:
    ```bash
    patch -p1 < "$LESSON/chart-0.2.0.patch"
    grep -A3 "^config" charts/allcsvideos-api/values.yaml
    helm upgrade api charts/allcsvideos-api -n prod --reuse-values | head -3
    kubectl -n prod get cm api-config -o jsonpath="{.data}"; echo
    helm upgrade api charts/allcsvideos-api -n prod --reset-then-reuse-values | head -3
    kubectl -n prod get cm api-config -o jsonpath="{.data}"; echo
    ```
    ```
    {"CACHE_TTL_SECONDS":"","DATABASE_URL":"...","LOG_LEVEL":"INFO"}
    {"CACHE_TTL_SECONDS":"300","DATABASE_URL":"...","LOG_LEVEL":"INFO"}
    ```

23. Pitfall 3 - editing release objects with kubectl:
    ```bash
    kubectl -n prod scale deploy api --replicas=1
    helm status api -n prod | grep STATUS
    helm upgrade api charts/allcsvideos-api -n prod -f env/values-prod.yaml
    helm upgrade api charts/allcsvideos-api -n prod -f env/values-prod.yaml --force-conflicts --wait --timeout 5m | head -6
    kubectl -n prod get deploy api
    ```
    Helm still says `deployed`; the next upgrade fails with `conflict with "kubectl" ... .spec.replicas`
    (Helm 4 uses server-side apply); `--force-conflicts` takes it back to `3/3`.

24. Pitfall 5 - floating versions. Without `--version` you get whatever is newest today:
    ```bash
    helm show chart oci://ghcr.io/stefanprodan/charts/podinfo | grep -E "^(version|appVersion)"
    ```

## Common mistakes
- Copying manifests per environment: a fix lands in one copy and not the other (the missing readiness probe).
- Copying a chart's whole `values.yaml` into yours: you hide your real changes and miss new defaults.
- Trusting `helm install --dry-run=server` as validation: pipe `helm template` into `kubectl apply --dry-run=server` (or a schema checker) in CI.
- Changing selector labels after the first install - they must never change.
- Putting secrets in values: they show up in `helm get values`, in every release Secret, and in git. Reference an existing Secret instead (Module 18, Lesson 2).
- `--reuse-values` ignores the new chart's defaults. Use `--reset-then-reuse-values`, or better, always pass your values files.
- Editing release objects with `kubectl`: Helm does not notice, and the next upgrade hits a server-side apply conflict.
- Giant templates full of nested `if`/`range`: keep templates close to plain YAML, use helpers, lint and render in every PR.
- No `--version` and `latest` tags: pin chart versions and image tags (the schema here refuses `latest`).
- Helm 4 renames: `--atomic` is now `--rollback-on-failure`, `--force` is now `--force-replace` (old flags warn).

## Clean up
```bash
helm uninstall demo -n demo
helm uninstall api -n staging
helm uninstall api -n prod
helm plugin uninstall diff
cd "$LESSON" && bash lab/down.sh
rm -rf ~/allcsvideos-helm /tmp/allcsvideos-api-0.1.0.tgz
```
(`lab/down.sh` deletes the whole cluster, so the uninstalls are optional.)

## Next
[M15-L02 · Kustomize](../m15-l02-kustomize/) - bases and overlays for dev, staging and production, with no templates at all.
