# M15-L02 · Kustomize
> Video: Module 15, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- Why per-environment copies drift, and how a base of plain YAML plus one small overlay per environment fixes it.
- How `kustomization.yaml` works: resources, generators (ConfigMaps/Secrets with a content hash), transformers.
- The two patch languages (strategic merge and JSON 6902), `images`, `replicas`, `namePrefix`, components and replacements.
- Why labels must stay out of selectors, how generators trigger real rollouts, and why `apply -k` never deletes.
- Promoting a release as a two-line commit, checked first with `kubectl diff`; when to pick Helm instead.

## Before you start
- Docker Desktop, `git`, and these tools (versions from the video):
  - `kind` v0.33.0, `kubectl` v1.37.x (it has Kustomize v5.8.1 built in)
  - standalone `kustomize` v5.8.3 (needed for `kustomize edit` and `kustomize build`)
  - optionally `tree`
- The previous lesson ([M15-L01 · Helm](../m15-l01-helm/)) for the comparison at the end.

## Files in this folder
| File | What it is |
|---|---|
| `lab/up.sh`, `lab/down.sh`, `lab/kind-cluster.yaml` | One-node kind cluster `kustomize-lab` (Kubernetes 1.37) and the four lab images, built and loaded |
| `app/api/`, `app/storefront/` | The lab API (prints its settings at start-up) and a static storefront page |
| `copies/dev|staging|prod/api.yaml` | The "before" picture: three hand-copied Deployments (staging has the wrong namespace) |
| `allcsvideos-k8s/base/` | Plain manifests (Namespace, api, storefront, Ingress `web`) + base `kustomization.yaml` |
| `allcsvideos-k8s/overlays/dev|staging|prod/` | One overlay per environment (prod also has the `api-resources.yaml` patch) |
| `allcsvideos-k8s/overlays/preview/` | A pull-request preview built on dev with `namePrefix: pr-142-` |
| `allcsvideos-k8s/components/debug/` | Optional component: `LOG_LEVEL=DEBUG` + an `api-debug` Service |
| `allcsvideos-k8s/demos/` | `generator-options` (hash off) and `old-fields` (`commonLabels`) demos |
| `steps/` | Overlay versions you copy in during the lesson (typo patch, bad/fixed labels, staging without debug) |

## Follow along

1. Start the lab and make working copies (the repo becomes a git repository):
   ```bash
   LESSON=$PWD                       # run from this lesson's folder
   bash lab/up.sh
   cp -R copies ~/copies
   cp -R allcsvideos-k8s ~/allcsvideos-k8s
   cd ~/allcsvideos-k8s && git init -q -b main && git add -A && git commit -qm "allcsvideos: base and overlays" && cd -
   ```

2. The problem: three copies of one Deployment.
   ```bash
   cd ~/copies
   ls
   grep -n "image:" */api.yaml
   sed -i.bak 's/api:1.4.0/api:1.5.0/' dev/api.yaml staging/api.yaml && rm */*.bak
   grep -n -e "namespace:" -e "image:" */api.yaml
   ```
   ```
   staging/api.yaml:5:  namespace: allcsvideos-prod
   staging/api.yaml:18:        image: allcsvideos/api:1.5.0
   ```
   The staging copy points at production - applying it would have shipped 1.5.0 into prod.

3. Which Kustomize do you have?
   ```bash
   cd ~/allcsvideos-k8s
   kubectl version --client
   kustomize version
   ```
   ```
   Client Version: v1.37.1
   Kustomize Version: v5.8.1
   v5.8.3
   ```

4. The repository and the base. Read `base/kustomization.yaml` (labels with `includeTemplates`, `commonAnnotations`,
   `configMapGenerator`, `secretGenerator` with a FAKE demo password), then render it:
   ```bash
   tree --noreport
   kubectl kustomize base | grep -e "^kind:" -e "^  name:"
   ```
   Eight objects; the generated ones get a hash suffix: `api-config-f7c9cmf6d4`, `db-creds-k2ctt9m6fk`.

5. Render all three overlays and compare:
   ```bash
   for e in dev staging prod; do echo "== $e"; kubectl kustomize overlays/$e | grep -e "^  namespace:" -e "replicas:" -e "image:" -e "host:" | sort | uniq -c; done
   ```
   ```
   == dev
         1         image: allcsvideos/api:1.5.0
         1   - host: dev.allcsvideos.com
         8   namespace: allcsvideos-dev
         2   replicas: 1
   ...
   == prod
         1         image: allcsvideos/api:1.4.0
         1   - host: allcsvideos.com
         7   namespace: allcsvideos-prod
         2   replicas: 3
   ```
   Prod has one object fewer: it does not use the debug component.

6. A patch that matches nothing (in a scratch copy):
   ```bash
   rm -rf /tmp/scratch && cp -R ~/allcsvideos-k8s /tmp/scratch
   cp "$LESSON/steps/api-resources-typo.yaml" /tmp/scratch/overlays/prod/api-resources.yaml
   kubectl kustomize /tmp/scratch/overlays/prod
   ```
   ```
   error: no resource matches strategic merge patch "Deployment.v1.apps/apii.[noNs]": ... failed to find unique target for patch ...
   ```

7. Name tools, old fields and generator options:
   ```bash
   kubectl kustomize overlays/preview | grep -e "^  name:" -e "name: pr-142"
   kustomize build demos/old-fields | grep -A3 "selector:"
   kubectl kustomize demos/generator-options
   ```
   Every name and every reference gets `pr-142-`; `commonLabels` prints a deprecation warning and puts the label into
   every selector; with `disableNameSuffixHash: true` the ConfigMap is plain `storefront-banner`.

8. Apply all three environments (three namespaces stand in for three clusters):
   ```bash
   kubectl apply -k overlays/dev
   kubectl apply -k overlays/staging
   kubectl apply -k overlays/prod --server-side
   kubectl get deploy -A -l course=devops -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image
   kubectl get ingress -A
   ```
   ```
   allcsvideos-dev       api          1       allcsvideos/api:1.5.0
   allcsvideos-prod      api          3       allcsvideos/api:1.4.0
   allcsvideos-staging   api          2       allcsvideos/api:1.5.0
   ```
   Ingress ADDRESS stays empty: this lab has no ingress controller.

9. Check what the API actually got:
   ```bash
   kubectl -n allcsvideos-dev logs deploy/api
   kubectl -n allcsvideos-prod logs deploy/api
   ```
   ```
   INFO api 1.5.0 starting · env=dev · log_level=DEBUG
   INFO database postgres:5432 · user api · password from file /etc/secrets/db-password (17 chars)
   INFO public host dev.allcsvideos.com
   ```
   `DEBUG` comes from the component, the host from the replacement.

10. Promote 1.5.0 to prod the way a pipeline would, then look before applying:
    ```bash
    cd overlays/prod
    kustomize edit set image allcsvideos/api:1.5.0 allcsvideos/storefront:1.5.0
    cd ../..
    git diff --stat
    grep -A1 "name: allcsvideos/" overlays/prod/kustomization.yaml
    kustomize build overlays/prod | kubectl diff -f -
    echo "exit code $?"
    ```
    `git diff --stat` shows 16 lines in and out (kustomize edit rewrites the file in its own key order once);
    `kubectl diff` shows only the two images `1.4.0` -> `1.5.0` and `generation`, and `exit code 1` (= differences).

11. Apply, wait, commit:
    ```bash
    kubectl apply -k overlays/prod --server-side
    kubectl -n allcsvideos-prod rollout status deploy/api
    git commit -qam "prod: promote 1.5.0"
    git log --oneline
    ```

12. A config change rolls the pods (thanks to the hash):
    ```bash
    sed -i.bak 's/LOG_LEVEL=WARNING/LOG_LEVEL=INFO/' overlays/prod/kustomization.yaml && rm overlays/prod/kustomization.yaml.bak
    kubectl kustomize overlays/prod | grep -e "name: api-config" -e "LOG_LEVEL"
    kubectl apply -k overlays/prod --server-side | grep -e configmap -e deployment
    kubectl -n allcsvideos-prod rollout status deploy/api
    kubectl -n allcsvideos-prod get configmaps
    kubectl -n allcsvideos-prod logs deploy/api | head -2
    git commit -qam "prod: LOG_LEVEL=INFO for a day"
    ```
    A new `api-config-2578chhttb`, a rollout, the old ConfigMap still listed, and `log_level=INFO`.

13. Labels that reach selectors - break it on purpose, then fix it:
    ```bash
    cp "$LESSON/steps/staging-labels-bad.yaml" overlays/staging/kustomization.yaml
    kubectl apply -k overlays/staging
    kubectl -n allcsvideos-staging get endpointslices -l kubernetes.io/service-name=api
    ```
    ```
    Deployment.apps "api" is invalid: spec.selector: ... field is immutable
    api-7n9jc   IPv4   <unset>   <unset>
    ```
    The Services were changed and now match no pods. The fix:
    ```bash
    cp "$LESSON/steps/staging-labels-fix.yaml" overlays/staging/kustomization.yaml
    kubectl apply -k overlays/staging
    kubectl -n allcsvideos-staging rollout status deploy/api
    kubectl -n allcsvideos-staging get endpointslices -l kubernetes.io/service-name=api
    git commit -qam "staging: environment label (templates only)"
    ```
    If the Service selector still contains `environment`, the endpoints stay empty until the new pods (which carry the
    label) are ready; then the slice lists pod IPs again.

14. `apply -k` does not delete. Remove the debug component from staging:
    ```bash
    cp "$LESSON/steps/staging-no-debug.yaml" overlays/staging/kustomization.yaml
    kubectl apply -k overlays/staging
    kubectl -n allcsvideos-staging get services
    kubectl -n allcsvideos-staging get configmaps
    kubectl apply --help | grep "prune is"
    git commit -qam "staging: no debug component"
    ```
    `api-debug` is still there, old generated ConfigMaps pile up, and `--prune is still in Alpha`.

Note: the video shows the render-only steps (patch typo, preview, old fields, generator options, labels) before the
applies; here the cluster steps follow the order they were actually run so every command works.

## Common mistakes
- Overlay sprawl: overlays on overlays. Keep one base, one layer of environments, plus components.
- Patches that do not match: the error is loud (good) - review the rendered output with `kubectl diff`.
- Real secrets in a `secretGenerator`: they sit in git in plain text. Keep fake values in git; use Sealed Secrets,
  SOPS or the External Secrets Operator for real ones (Module 18).
- Labels in selectors (`includeSelectors: true` or old `commonLabels`): immutable-field errors and a Service that
  briefly matches nothing. Use `includeTemplates: true` instead.
- Forgetting that `apply -k` never prunes: removed objects and old ConfigMaps stay until something deletes them
  (Argo CD's prune, next lesson).
- Old fields: `patchesStrategicMerge`, `patchesJson6902` and `vars` are deprecated in Kustomize 5 - use `patches`
  and `replacements` (`kustomize edit fix` converts them).
- Order: a component runs before the overlay's own patches, so a replacement inside a component copies the base value
  (`set-by-overlay`). Keep the replacement in the overlay.
- Remote bases: pin a tag or commit (`?ref=v1.2.0`), never a branch.

## Clean up
```bash
cd "$LESSON" && bash lab/down.sh
rm -rf ~/copies ~/allcsvideos-k8s /tmp/scratch
```

## Next
[M15-L03 · GitOps with Argo CD](../m15-l03-gitops-with-argo-cd/) - Git as the source of truth, sync, drift detection and app-of-apps.
