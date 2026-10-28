# M15-B01 · Deploy allcsvideos to EKS with Helm and Argo CD
> Video: Module 15, Build 1. Watch it first, then follow along here.

> **This build costs real money.** It runs on the EKS cluster from
> [M15-L04](../m15-l04-managed-kubernetes-on-eks/): the EKS control plane (**USD 0.10 per hour**), one t3.medium
> node, a NAT gateway and an Elastic IP, all billed per hour while they exist. This build itself adds only pods
> (the storefront Service is a ClusterIP, so no load balancer). Do it in one sitting, then run the
> [Clean up](#clean-up) section **and** the M15-L04 teardown the same day.

## What you'll learn
- A GitOps release pipeline on a real cluster: a Helm chart in a deploy repo, Argo CD pulling it into EKS, nobody running `kubectl apply`.
- Running Argo CD in **core mode** (3 pods, no API server/UI) and why the `default` AppProject then has to be declared.
- Canary releases with Argo Rollouts: a `Rollout` instead of a Deployment, `setWeight: 50`, a manual pause, promote and abort.
- Why, without a traffic router, the canary weight comes from pod counts.
- How the readiness probe, abort, `git revert` and self-heal keep a bad release small.

## Before you start
- The running cluster `allcs-eks` from [M15-L04](../m15-l04-managed-kubernetes-on-eks/), with `kubectl` connected
  (`aws eks update-kubeconfig --name allcs-eks --region us-east-1`). Delete that lesson's `web` demo Service first.
- AWS CloudShell (what the video used), with `git`, `jq` and `openssl` (preinstalled there), plus the tools in
  `tools.sh`: Helm v4.3.1, the `argocd` CLI v3.5.5, the `kubectl-argo-rollouts` plugin v1.10.1.
- Helm ([M15-L01](../m15-l01-helm/)) and Argo CD ([M15-L03](../m15-l03-gitops-with-argo-cd/)).

**About the sandbox.** The video ran in a restricted sandbox: one self-managed node, at most **3 pods per namespace**,
pods capped at 256m CPU / 512Mi. That is why Argo CD runs in core mode here, with small resources, and why the
storefront has one replica. Two lab stand-ins: **podinfo** 6.14.1 -> 6.15.0 plays the storefront (it reports its
version and pod on every request), and **Gitea** runs inside the cluster on `emptyDir` volumes (lab only - in
production this is GitHub or GitLab).

## Files in this folder
| File | What it is |
|---|---|
| `tools.sh` | Installs helm v4.3.1, argocd v3.5.5 and kubectl-argo-rollouts v1.10.1 into `~/bin` (Linux x86_64) |
| `helpers.sh` | Shell helpers: `hit N` (N requests from inside the cluster, counted by version and pod), `waitphase PHASE`, `push` |
| `platform/gitea.yaml` | Namespace `git` + Gitea 28.1.0-rootless Deployment (emptyDir) + Service on port 3000 |
| `platform/argocd-values.yaml` | Values for the `argo/argo-cd` chart 10.10.5: core only (controller, repo server, Redis), small resources |
| `platform/rollouts-values.yaml` | Values for the `argo/argo-rollouts` chart 2.43.8: one controller, no dashboard |
| `platform/project.yaml` | The `default` AppProject, declared by hand (argocd-server normally creates it) |
| `platform/app.yaml` | The `storefront` Application: chart `charts/storefront` + `values-prod.yaml`, automated prune + self-heal, resources finalizer |
| `allcsvideos-deploy/charts/storefront/` | The deploy repo: chart 0.1.0 (appVersion 6.14.1) with a `Rollout` + `Service`, `values.yaml`, `values-prod.yaml` |

## Follow along

1. Tools and helpers (in CloudShell, from this folder):
   ```bash
   bash tools.sh && source ~/.bashrc
   source helpers.sh
   helm repo add argo https://argoproj.github.io/argo-helm && helm repo update argo
   ```

2. Check the chart before it goes into Git:
   ```bash
   cd allcsvideos-deploy
   helm lint charts/storefront -f charts/storefront/values-prod.yaml
   helm template storefront charts/storefront -f charts/storefront/values-prod.yaml -s templates/rollout.yaml
   cd ..
   ```
   `1 chart(s) linted, 0 chart(s) failed`; the rendered `Rollout` has image `ghcr.io/stefanprodan/podinfo:6.14.1`,
   the `/readyz` readiness probe, and the steps `setWeight: 50` and `pause: {}` (a pause with no duration waits for a human).

3. Step one - the cluster:
   ```bash
   kubectl get nodes; aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceType" --output text
   ```
   One node `Ready` on `v1.37.0-eks-...`, and `t3.medium`.

4. Step two - the Git server, a user `asha` with a random password, and a token kept only in a shell variable:
   ```bash
   kubectl apply -f platform/gitea.yaml && kubectl rollout status deploy/gitea -n git --timeout=240s
   kubectl exec -n git deploy/gitea -- gitea admin user create --username asha --email asha@example.com --random-password --must-change-password=false >/dev/null
   TOKEN=$(kubectl exec -n git deploy/gitea -- gitea admin user generate-access-token --username asha --token-name deploy --scopes write:repository,write:user --raw)
   kubectl port-forward -n git svc/gitea 3000:3000 >/dev/null 2>&1 &
   ```
   (Creating a repository through the API needs the `write:user` scope - the first try in the video lacked it.)

5. Step three - Argo CD, core only. `redisSecretInit` is off (its Job pod would count against the 3-pod cap), so
   create the Redis password Secret yourself; it never appears on screen:
   ```bash
   kubectl create namespace argocd && kubectl create secret generic argocd-redis -n argocd --from-literal=auth=$(openssl rand -hex 16)
   cat platform/argocd-values.yaml
   time helm install argocd argo/argo-cd --version 10.10.5 -n argocd -f platform/argocd-values.yaml --wait --timeout 10m 2>&1 | tail -5
   kubectl get pods -n argocd
   ```
   ```
   argocd-application-controller-0      1/1     Running
   argocd-redis-...                     1/1     Running
   argocd-repo-server-...               1/1     Running
   ```
   The chart's notes talk about a UI login: in core mode there is no UI server, so ignore them.

6. Step four - Argo Rollouts:
   ```bash
   helm install argo-rollouts argo/argo-rollouts --version 2.43.8 -n argo-rollouts --create-namespace -f platform/rollouts-values.yaml --wait --timeout 5m 2>&1 | tail -4; kubectl get pods -n argo-rollouts
   ```
   `STATUS: deployed`, `REVISION: 1`, one `argo-rollouts-...` pod Running.

7. Step five - the deploy repository:
   ```bash
   curl -s -X POST -H "Authorization: token $TOKEN" -H "Content-Type: application/json" -d "{\"name\":\"allcsvideos-deploy\",\"private\":false,\"default_branch\":\"main\"}" http://localhost:3000/api/v1/user/repos | jq -r '.full_name + " " + .clone_url'
   cp -R allcsvideos-deploy ~/allcsvideos-deploy && cd ~/allcsvideos-deploy
   git init -q -b main
   find . -path ./.git -prune -o -type f -print | sort
   git add . && git commit -qm "storefront chart, production on 6.14.1"
   git remote add origin http://localhost:3000/asha/allcsvideos-deploy.git
   push && git log --oneline
   cd -
   ```
   (Set `git config --global user.name/user.email` first if CloudShell asks.)

8. Step six - tell Argo CD. In core mode nobody creates the `default` project, so the Application would show
   `InvalidSpecError: ... project default which does not exist`. Declare it, then apply the Application:
   ```bash
   cat platform/project.yaml; kubectl apply -f platform/project.yaml
   cat platform/app.yaml; kubectl apply -f platform/app.yaml
   for i in $(seq 1 40); do S=$(kubectl get application storefront -n argocd -o jsonpath="{.status.sync.status} {.status.health.status}"); [ "$S" = "Synced Healthy" ] && break; sleep 6; done; echo "$S after $((i*6))s"; kubectl get application storefront -n argocd
   ```
   kubectl prints a `Warning` about the finalizer name format - a warning, not an error. Then `Synced Healthy after 12s`.

9. Look at it from Argo CD, Argo Rollouts and the app itself:
   ```bash
   argocd app get storefront --core 2>&1 | head -24
   kubectl argo rollouts get rollout storefront -n allcsvideos
   kubectl get svc storefront -n allcsvideos; kubectl exec -n git deploy/gitea -- wget -qO- http://storefront.allcsvideos.svc/ | head -12
   ```
   ```
   Sync Status:        Synced to main (5ee9ed0)
   ...
   Status:          ✔ Healthy
   Strategy:        Canary
     Step:          2/2
   Images:          ghcr.io/stefanprodan/podinfo:6.14.1 (stable)
   ...
     "version": "6.14.1",
     "message": "allcsvideos storefront - production",
   ```
   (`--core` starts a local API process just for that command; your hashes and pod names will differ.)

10. A real release, the GitOps way:
    ```bash
    hit 10
    cd ~/allcsvideos-deploy && sed -i "s/6.14.1/6.15.0/" charts/storefront/values-prod.yaml && git diff && git commit -qam "storefront 6.15.0" && push && git log --oneline
    kubectl annotate application storefront -n argocd argocd.argoproj.io/refresh=normal --overwrite
    waitphase Paused
    kubectl argo rollouts get rollout storefront -n allcsvideos
    kubectl get application storefront -n argocd
    hit 20
    ```
    ```
    phase Paused after 12s
    Status:          ॥ Paused
    Message:         CanaryPauseStep
      Step:          1/2
      SetWeight:     50
      ActualWeight:  50
    Images:          ghcr.io/stefanprodan/podinfo:6.14.1 (stable)
                     ghcr.io/stefanprodan/podinfo:6.15.0 (canary)
    storefront   Synced        Suspended
         10 6.14.1 storefront-f864976b6-7dlgs
         10 6.15.0 storefront-66df9db5b6-b8mvd
    ```
    The refresh annotation only saves time; without it Argo CD notices within about three minutes. There is no
    traffic router: the Service spreads requests over ready pods, so "50%" means one canary pod next to one stable pod.

11. Promote:
    ```bash
    kubectl argo rollouts promote storefront -n allcsvideos
    waitphase Healthy; kubectl argo rollouts get rollout storefront -n allcsvideos
    hit 10
    ```
    `Step: 2/2`, `6.15.0 (stable)`, revision 1 `ScaledDown`; all 10 answers from 6.15.0.

12. A bad release, staged on purpose. podinfo's `--unready` flag means "ready state is never reached":
    ```bash
    printf "extraArgs: [\"--unready\"]\n" >> charts/storefront/values-prod.yaml && git diff && git commit -qam "storefront: new startup flag" && push && git log --oneline | head -3
    kubectl annotate application storefront -n argocd argocd.argoproj.io/refresh=normal --overwrite; sleep 60; kubectl argo rollouts get rollout storefront -n allcsvideos
    hit 10
    ```
    ```
    Status:          ◌ Progressing
      Step:          0/2
      ActualWeight:  0
    │     └──□ storefront-6c9677f8f8-w22vg  Pod  ✔ Running  ...  ready:0/1
         10 6.15.0 storefront-66df9db5b6-b8mvd
    ```
    The canary never became ready, so it got no traffic.

13. Abort, then fix the source with `git revert`:
    ```bash
    kubectl argo rollouts abort storefront -n allcsvideos; sleep 15; kubectl argo rollouts get rollout storefront -n allcsvideos
    kubectl get application storefront -n argocd
    git revert --no-edit HEAD >/dev/null && push && git log --oneline | head -4
    kubectl annotate application storefront -n argocd argocd.argoproj.io/refresh=normal --overwrite; waitphase Healthy; kubectl get application storefront -n argocd
    kubectl argo rollouts get rollout storefront -n allcsvideos
    ```
    After abort: `✖ Degraded`, `RolloutAborted: Rollout aborted update to revision 3`, and the Application
    `Synced Degraded` (the cluster still matches Git). After the revert: `Synced Healthy`, and the Rollout reuses the
    stable ReplicaSet as revision 4 - same pod, no new canary.

14. Drift: scale by hand, watch self-heal put Git's value back; check the sandbox cap:
    ```bash
    kubectl scale rollout storefront -n allcsvideos --replicas=3; sleep 2; kubectl get rollout storefront -n allcsvideos -o jsonpath="{.spec.replicas}"; echo; sleep 25; kubectl get rollout storefront -n allcsvideos -o jsonpath="{.spec.replicas}"; echo
    kubectl get pods -A --no-headers | awk "{print \$1}" | sort | uniq -c
    hit 10
    ```
    `1` and `1`; pods per namespace: 1 allcsvideos, 3 argocd, 1 argo-rollouts, 1 git, 4 kube-system.

Explained but not run: AnalysisTemplates with Prometheus (Module 16), traffic routers for exact weights (AWS Load
Balancer Controller, Gateway API, Istio, Traefik), ApplicationSets per environment, CI or Argo CD Image Updater
writing the tag, full HA Argo CD, blue-green, Rollouts notifications, Flagger.

## Common mistakes
- Running a full Argo CD install where a namespace pod cap applies: core mode needs the `default` AppProject declared by hand.
- Trusting the canary weight without a traffic router: with one replica, 50% is "one pod each", and 10% cannot exist.
- No readiness probe on the pod template: then an unready canary would get traffic. The probe is what kept every user on the good version.
- Thinking abort fixes things: it stops the damage, but Git still asks for the bad version (`Synced`, `Degraded`). Fix it with `git revert`.
- Scaling or editing the Rollout by hand: self-heal puts Git's value back within seconds.
- Keeping Git data on `emptyDir`: fine for a lab, never for production.
- Leaving the cluster running: the control plane, node and NAT gateway bill every hour.

## Clean up
Run these from this lesson's folder (`cd -` back to it from `~/allcsvideos-deploy`).

1. Delete the Application first - its finalizer removes everything it deployed - and check no load balancer is left:
   ```bash
   kubectl delete -f platform/app.yaml --wait=true; for i in $(seq 1 30); do N=$(aws elb describe-load-balancers --query "length(LoadBalancerDescriptions)"); [ "$N" = "0" ] && break; sleep 10; done; echo "load balancers left: $N"
   ```
2. Remove the platform (the charts keep their CRDs by a resource policy; deleting those is a deliberate extra step):
   ```bash
   helm uninstall argo-rollouts -n argo-rollouts; helm uninstall argocd -n argocd; kubectl delete ns git argocd argo-rollouts allcsvideos --ignore-not-found --wait=true
   kubectl delete crd analysisruns.argoproj.io analysistemplates.argoproj.io clusteranalysistemplates.argoproj.io experiments.argoproj.io rollouts.argoproj.io applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
   kill %1 2>/dev/null; rm -rf ~/allcsvideos-deploy; unset TOKEN
   ```
3. Destroy the cluster with the full teardown in [M15-L04 · Clean up](../m15-l04-managed-kubernetes-on-eks/#clean-up),
   including its three real surprises: the access entry the sandbox would not delete (`terraform state rm`), a
   network interface left by the VPC CNI, and the `eks-cluster-sg-...` security group. Finish with the final check:
   0 instances, 0 clusters, 0 load balancers.

## Next
[M16-L01 · The Three Pillars and What to Measure](../../observability/m16-l01-the-three-pillars-and-what-to-measure/) - golden signals, RED and USE.
