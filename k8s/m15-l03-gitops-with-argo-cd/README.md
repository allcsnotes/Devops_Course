# M15-L03 · GitOps with Argo CD
> Video: Module 15, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- GitOps and the four OpenGitOps principles: declarative, versioned and immutable, pulled automatically, continuously reconciled.
- Push (a pipeline holding cluster credentials) vs pull (an agent in the cluster reading Git with read-only access).
- Argo CD's parts (repo server, application controller, API server, Redis, ApplicationSet controller) and the Application resource: source, destination, sync policy; Sync status vs Health status.
- Drift detection, self-heal, prune, and why rollback means `git revert`.
- App of apps, ApplicationSets, hooks and sync waves; how secrets should (not) live in Git; Argo CD vs Flux.

## Before you start
- Docker Desktop, `git`, `curl`, and these tools:
  - `kind` v0.33.0 and `kubectl` (the cluster runs Kubernetes 1.36.4: the Argo CD docs list 1.33-1.36 as tested for 3.5)
  - the `argocd` CLI v3.5.6 (from the [v3.5.6 release](https://github.com/argoproj/argo-cd/releases/tag/v3.5.6))
  - optional: `ts` (from moreutils) to timestamp the watch output
- Kustomize bases and overlays from [M15-L02 · Kustomize](../m15-l02-kustomize/). Two terminals.

## Files in this folder
| File | What it is |
|---|---|
| `lab/up.sh`, `lab/down.sh`, `lab/kind-cluster.yaml` | kind cluster `argocd-lab`, lab images, and Gitea (`gitea:3000`) with FAKE lab accounts asha, priya and a read-only `argocd-bot` |
| `argocd/kustomization.yaml`, `argocd/namespace.yaml` | Argo CD v3.5.6 from the official install manifest (pinned URL) + lab patches: no Dex, no notifications, UI on node port 30093, slower probes |
| `app/` | The lab API and storefront (same apps as M15-L02) |
| `allcsvideos-deploy/` | The deploy repo: `storefront/` (base + dev/staging/prod), `api/` (base with PreSync/PostSync hook Jobs + prod), `monitoring/` placeholder, `apps/api.yaml` |
| `later/apps/storefront.yaml`, `later/apps/monitoring.yaml`, `later/bootstrap/root.yaml` | Added for app of apps |
| `later/apps/storefront-envs.yaml` | The ApplicationSet (list generator: dev, staging) |

## Follow along

1. Start the lab (cluster, images, Gitea):
   ```bash
   LESSON=$PWD                       # run from this lesson's folder
   bash lab/up.sh
   ```

2. Install Argo CD 3.5.6 with server-side apply (some Argo CD CRDs are too big for client-side apply's annotation):
   ```bash
   head -12 argocd/kustomization.yaml
   kubectl apply -k argocd/ --server-side --force-conflicts | tail -8
   kubectl wait --for=condition=Available deployment --all -n argocd --timeout=900s
   kubectl get pods -n argocd
   kubectl get svc argocd-server -n argocd
   ```
   ```
   argocd-application-controller-0                     1/1     Running
   argocd-applicationset-controller-...                1/1     Running
   argocd-redis-...                                    1/1     Running
   argocd-repo-server-...                              1/1     Running
   argocd-server-...                                   1/1     Running
   argocd-server   NodePort   ...   80:...../TCP,443:30093/TCP
   ```
   (On a slow laptop a few `Timeout` lines can appear; just run the apply again.)

3. In a **second terminal**, forward the server, then log in from the first one. The initial password is read from a
   Secret and never shown; then set a (fake) lab password and delete the initial secret:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443        # second terminal, leave it running
   ```
   ```bash
   argocd login localhost:8080 --username admin --password "$(argocd admin initial-password -n argocd | head -1)" --insecure
   argocd account update-password --current-password "$(argocd admin initial-password -n argocd | head -1)" --new-password fake-lab-pass-argocd
   kubectl delete secret argocd-initial-admin-secret -n argocd
   argocd version | head -4
   ```
   The web UI is at https://localhost:8080 (or https://localhost:8093 through the node port); user `admin`.

4. Push the deploy repo to Gitea (private). Your laptop uses `localhost:3000`; Argo CD, inside the cluster, uses `gitea:3000`:
   ```bash
   cp -R allcsvideos-deploy ~/allcsvideos-deploy && cd ~/allcsvideos-deploy
   tree --noreport
   git init -q -b main && git add . && git commit -qm 'storefront and api: prod overlays, api Application'
   git remote add origin http://asha:fake-lab-pass-asha@localhost:3000/allcsvideos/allcsvideos-deploy.git
   git push -q -u origin main
   git log --oneline
   ```

5. Give Argo CD read access with the bot's read-only token (stored as a Secret inside the cluster):
   ```bash
   REPO=http://gitea:3000/allcsvideos/allcsvideos-deploy.git
   argocd repo add $REPO --username argocd-bot --password "$(cat ~/.argocd-lab/argocd-bot-token)"
   argocd repo list
   ```
   `STATUS` should be `Successful`.

6. The first Application, from the CLI (manual sync):
   ```bash
   argocd app create storefront --repo $REPO --path storefront/overlays/prod --dest-server https://kubernetes.default.svc --dest-namespace allcsvideos-prod --sync-option CreateNamespace=true
   argocd app get storefront
   argocd app sync storefront
   argocd app wait storefront --health --timeout 300 | tail -12
   kubectl get pods -n allcsvideos-prod
   ```
   ```
   Sync Status:        OutOfSync from  (fde78a8)
   Health Status:      Missing
   ...
   Sync Status:        Synced to  (fde78a8)
   Health Status:      Healthy
   storefront-66766564d4-fjb2n   1/1     Running
   storefront-66766564d4-pcn7z   1/1     Running
   ```
   (Your commit hashes will differ.) Open the UI to see the same tree.

7. The GitOps way: the Application itself in Git (`apps/api.yaml`: automated, prune, selfHeal). Apply it once:
   ```bash
   kubectl apply -f apps/api.yaml
   date +%T
   argocd app wait api --health --sync --timeout 600 >/dev/null; date +%T
   argocd app get api
   kubectl logs job/db-migrate -n allcsvideos-prod
   kubectl logs job/smoke-test -n allcsvideos-prod
   kubectl get pods -n allcsvideos-prod -l app=api
   ```
   ```
   batch  Job         db-migrate             Succeeded  Synced   PreSync
          ConfigMap   api-config-22c2cg9859  Synced
          Service     api                    Synced     Healthy
   apps   Deployment  api                    Synced     Healthy
   batch  Job         smoke-test             Running    Synced   PostSync
   migrating schema for api 1.4.0
   migration done
   smoke test ok: api 1.4.0 on api-...
   ```

8. Launch day: Priya deploys through Git only. In the **second terminal** (stop the port-forward first, or open a
   third one) watch the Application:
   ```bash
   kubectl get application api -n argocd -w | ts '%H:%M:%S'
   ```
   In the first terminal, as Priya, in her own clone:
   ```bash
   git clone -q http://priya:fake-lab-pass-priya@localhost:3000/allcsvideos/allcsvideos-deploy.git ~/priya-deploy && cd ~/priya-deploy
   git config user.name Priya && git config user.email priya@example.com
   sed -i.bak 's/newTag: 1.4.0/newTag: 1.5.0/; s/count: 2/count: 3/' api/overlays/prod/kustomization.yaml && rm api/overlays/prod/kustomization.yaml.bak
   git diff
   git commit -qam 'api 1.5.0, 3 replicas for the launch'
   git push -q && date +%T
   ```
   No webhook, no refresh: within about 3 minutes (120 s polling + up to 60 s jitter; the video measured 3 m 50 s on a
   busy laptop) the watch turns `OutOfSync`, then `Synced Progressing`, then `Synced Healthy`. Then:
   ```bash
   cd ~/allcsvideos-deploy
   argocd app get api --show-operation | sed -n '12,22p'
   argocd app history api
   kubectl get pods -n allcsvideos-prod -l app=api
   kubectl logs job/db-migrate -n allcsvideos-prod
   ```
   Two history entries, each pinned to a commit; three new pods; the migration ran again for 1.5.0.
   Restart the port-forward in the second terminal for the next steps.

9. Drift, staged on purpose. The storefront app is still manual:
   ```bash
   kubectl scale deployment storefront -n allcsvideos-prod --replicas=5
   sleep 5; argocd app get storefront | tail -9
   argocd app diff storefront
   argocd app set storefront --sync-policy automated --auto-prune --self-heal
   argocd app wait storefront --sync --health --timeout 300 | tail -3
   kubectl get deployment storefront -n allcsvideos-prod
   ```
   ```
   <   replicas: 5
   ---
   >   replicas: 2
   ...
   storefront   2/2     2            2
   ```

10. Self-heal on the API (watch it in another terminal with `kubectl get deployment api -n allcsvideos-prod -w | ts '%H:%M:%S'`):
    ```bash
    kubectl scale deployment api -n allcsvideos-prod --replicas=6; date +%T
    ```
    Within seconds the desired count goes back to 3. Now a "2 a.m. hotfix":
    ```bash
    kubectl set image deployment/api api=allcsvideos/api:1.4.0 -n allcsvideos-prod; date +%T
    sleep 40; kubectl get deployment api -n allcsvideos-prod -o wide | cut -c1-110
    argocd app history api | tail -4
    ```
    The image is `allcsvideos/api:1.5.0` again, and history did not change: self-heal restored Git.

11. Prune: Priya removes the Diwali banner from Git.
    ```bash
    kubectl get configmap promo-banner -n allcsvideos-prod
    cd ~/priya-deploy
    git pull -q
    git rm -q storefront/base/banner.yaml
    sed -i.bak '/banner.yaml/d' storefront/base/kustomization.yaml && rm storefront/base/kustomization.yaml.bak
    git commit -qam 'storefront: the Diwali banner is over'
    git push -q
    cd ~/allcsvideos-deploy
    argocd app get storefront --refresh | tail -6
    sleep 10; kubectl get configmap promo-banner -n allcsvideos-prod
    ```
    ```
    Error from server (NotFound): configmaps "promo-banner" not found
    ```

12. Rollback: the CLI refuses with auto-sync on; use `git revert`.
    ```bash
    argocd app history api
    argocd app rollback api 1
    git pull -q
    git log --oneline
    git revert --no-edit $(git log --format=%h -1 --grep='api 1.5.0')
    git show --stat HEAD | tail -4
    git push -q
    argocd app get api --refresh >/dev/null; argocd app wait api --sync --health --timeout 300 >/dev/null
    argocd app get api | sed -n '11,13p'
    kubectl get deployment api -n allcsvideos-prod -o wide | cut -c1-110
    argocd app history api | tail -3
    ```
    ```
    ... rollback cannot be initiated when auto-sync is enabled
    ...
    api    2/2   ...   allcsvideos/api:1.4.0
    ```

13. App of apps: put every Application in Git, and apply only `root` by hand.
    ```bash
    mkdir -p bootstrap
    cp "$LESSON/later/apps/storefront.yaml" "$LESSON/later/apps/monitoring.yaml" apps/
    cp "$LESSON/later/bootstrap/root.yaml" bootstrap/
    tree --noreport apps bootstrap
    git add apps bootstrap && git commit -qm 'app of apps: root, storefront, monitoring' && git push -q
    kubectl apply -f bootstrap/root.yaml
    argocd app wait root --sync --health --timeout 300 | tail -6
    argocd app list
    ```
    Root creates `monitoring` and takes over `storefront` and `api`; four applications, all Synced and Healthy.

14. An ApplicationSet (one template, a list generator for dev and staging):
    ```bash
    cp "$LESSON/later/apps/storefront-envs.yaml" apps/
    git add apps && git commit -qm 'storefront dev and staging via an ApplicationSet' && git push -q
    argocd app get root --refresh | tail -6
    sleep 30; argocd app list
    kubectl get pods -A -l app=storefront
    kubectl get applicationset -n argocd
    ```
    Six applications; `storefront-dev` and `storefront-staging` run one pod each on 1.5.0.

Things the lesson explains but does not run: sync windows, projects and RBAC, custom Lua health checks,
Sealed Secrets / External Secrets / SOPS (Module 18), Flux, and Argo CD Image Updater.

## Common mistakes
- `kubectl` edits fighting self-heal: the hotfix lasted under 40 seconds. Change Git, or pause auto-sync for that app on purpose and say so.
- Secrets in Git: base64 is not encryption, and Git history is forever. Encrypt them or keep them out (Module 18).
- One giant Application for everything: one broken manifest blocks every sync. Split by service and environment; tie them together with app of apps or ApplicationSets.
- Automated sync with prune on production and no review in front: protect `main` with required reviews, prune with care.
- Mixing CI and CD: CI builds and tests, then commits the new tag to the deploy repo; Argo CD deploys. The pipeline never needs cluster credentials.
- Planning on `argocd app rollback`: with auto-sync it is refused; without it, Git and the cluster disagree. Roll back with `git revert`.
- Using the `default` project in production: give each team its own project.

## Clean up
```bash
cd "$LESSON" && bash lab/down.sh
rm -rf ~/allcsvideos-deploy ~/priya-deploy
argocd context localhost:8080 --delete 2>/dev/null || true
```
Stop the port-forward in the second terminal with Ctrl+C.

## Next
[M15-L04 · Managed Kubernetes on EKS](../m15-l04-managed-kubernetes-on-eks/) - provisioning with Terraform, nodes, and IAM roles for service accounts.
