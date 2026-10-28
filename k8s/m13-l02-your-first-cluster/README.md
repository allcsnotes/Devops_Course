# M13-L02 · Your First Cluster
> Video: Module 13, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- Build a three-node Kubernetes cluster with kind from a YAML config, and load a locally built image into it.
- What a kubeconfig holds (clusters, users, contexts), how the current context decides where every command goes, and how to merge several files with `KUBECONFIG`.
- The kubectl grammar (verb, resource, name, flags), namespaces, `api-resources`, `explain`, `describe`, `-o yaml/json/jsonpath`, `logs` and `exec`.
- `kubectl create` vs `kubectl apply`, and the desired-state control loop: watch, compare, act.
- Why drift happens (`kubectl scale`, `kubectl edit`) and how `kubectl diff` and the next `apply` catch it.

## Before you start
- Docker Desktop (or Docker Engine on Linux), running, with about 4 GB of memory for Docker (this lesson briefly runs three clusters).
- kind **v0.33.0** (https://kind.sigs.k8s.io/docs/user/quick-start/#installation) and kubectl **v1.37.1** (https://kubernetes.io/docs/tasks/tools/).
- Node image `kindest/node:v1.37.0` (Kubernetes 1.37.0), pinned in the two cluster configs.
- A bash or zsh shell (on Windows: WSL or Git Bash). Optional: `jq`.
- Concepts from [M13-L01](../m13-l01-why-orchestration/). Run every command from this folder.

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | Your main cluster `lab`: one control plane and two workers; publishes `127.0.0.1:30080` for later NodePort demos |
| `dev-staging-cluster.yaml` | A one-node cluster config, used twice for the `lab-dev` and `lab-staging` stand-ins |
| `web/Dockerfile`, `web/index.html` | A tiny allcsvideos storefront image: `nginxinc/nginx-unprivileged:1.29.8-alpine` plus one HTML page, port 8080 |
| `manifests/web-2-replicas.yaml` | Reference copy of the `web.yaml` you generate in step 9 |
| `manifests/web-4-replicas.yaml` | Reference copy of `web.yaml` after you change replicas to 4 in step 13 |

## Follow along

1. Check your tools and read the cluster config.
   ```bash
   kind version
   kubectl version --client
   cat kind-cluster.yaml
   ```
   `extraPortMappings` publishes node port 30080 on your laptop's `127.0.0.1`, so a browser can reach a NodePort service in later lessons.

2. Build the storefront image.
   ```bash
   docker build -t web:1.0 web/
   ```

3. Create the cluster. Note the line `Set kubectl context to "kind-lab"`: creating a cluster changes your current context.
   ```bash
   kind create cluster --config kind-cluster.yaml
   kind get clusters
   docker ps --filter label=io.x-k8s.kind.cluster=lab --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
   kubectl get nodes
   ```
   You should see:
   ```
   NAMES               IMAGE                  PORTS
   lab-control-plane   kindest/node:v1.37.0   127.0.0.1:30080->30080/tcp, 127.0.0.1:58345->6443/tcp
   lab-worker          kindest/node:v1.37.0
   lab-worker2         kindest/node:v1.37.0
   ```
   Nodes say `NotReady` for a few seconds while the pod network starts. Run `kubectl get nodes` again until all three are `Ready`, then:
   ```bash
   kubectl cluster-info
   ```
   Your API server port (58345 in the video) will differ.

4. Load the image into the cluster. Each kind node runs its own containerd with its own image store; without this, a pod would try Docker Hub and fail.
   ```bash
   kind load docker-image web:1.0 --name lab
   docker exec lab-worker crictl images | grep -E 'IMAGE|web'
   ```
   You should see:
   ```
   Image: "web:1.0" with ID "sha256:..." not yet present on node "lab-control-plane", loading...
   ...
   IMAGE                       TAG     IMAGE ID        SIZE
   docker.io/library/web       1.0     e17be2685c0db   23.1MB
   ```

5. Look at the kubeconfig kind wrote. Only you should be able to read it (mode 600). The second command prints the file with the certificate and key data redacted.
   ```bash
   ls -l ~/.kube/config
   sed -E 's/(-data:) .*/\1 REDACTED/' ~/.kube/config
   kubectl config view
   kubectl config get-contexts
   kubectl config current-context
   ```
   You should see three lists, `clusters`, `contexts` and `users`, plus `current-context: kind-lab`. `kubectl config view` hides the secrets as `DATA+OMITTED`. If you already had other clusters, your file shows them too.

6. Create the two stand-in clusters, `lab-dev` and `lab-staging`, each with its **own** kubeconfig file, and deploy `web` to both (the setup of Priya's story).
   ```bash
   kind create cluster --name lab-dev     --config dev-staging-cluster.yaml --kubeconfig ~/.kube/dev.yaml
   kind create cluster --name lab-staging --config dev-staging-cluster.yaml --kubeconfig ~/.kube/staging.yaml
   for env in dev staging; do
     kind load docker-image web:1.0 --name lab-$env
     kubectl --kubeconfig ~/.kube/$env.yaml create namespace allcsvideos
     kubectl --kubeconfig ~/.kube/$env.yaml apply -f manifests/web-2-replicas.yaml
     kubectl --kubeconfig ~/.kube/$env.yaml rollout status deployment/web -n allcsvideos
   done
   ```

7. Merge the three files with `KUBECONFIG` (colon-separated). Nothing is copied; kubectl merges them in memory and the first file wins on conflicts.
   ```bash
   export KUBECONFIG=~/.kube/config:~/.kube/dev.yaml:~/.kube/staging.yaml
   kubectl config get-contexts
   ```
   You should see:
   ```
   CURRENT   NAME              CLUSTER           AUTHINFO          NAMESPACE
   *         kind-lab          kind-lab          kind-lab
             kind-lab-dev      kind-lab-dev      kind-lab-dev
             kind-lab-staging  kind-lab-staging  kind-lab-staging
   ```
   Switch, and the same command talks to a different cluster:
   ```bash
   kubectl config use-context kind-lab-dev
   kubectl get deployments -n allcsvideos
   kubectl config use-context kind-lab
   kubectl get deployments -n allcsvideos
   ```
   On dev you see `web 2/2`; on `kind-lab`: `No resources found in allcsvideos namespace.`

8. Put the context in your prompt, so you always know where you are.
   ```bash
   kctx(){ kubectl config current-context; }
   PS1='[$(kctx)] \u@\h:\w\$ '           # bash
   ```
   In zsh (the macOS default) use instead: `setopt PROMPT_SUBST; PROMPT='[$(kctx)] %n@%m:%~%# '`. Put the lines in your `~/.bashrc` or `~/.zshrc` to keep them. Popular tools do the same job: kube-ps1, kubectx and kubens.
   ```bash
   kubectl config use-context kind-lab-dev
   kubectl config set-context --current --namespace=allcsvideos
   kubectl get pods
   kubectl config get-contexts
   kubectl config use-context kind-lab
   ```
   Now `kubectl get pods` without `-n` lists the web pods, and `get-contexts` shows `allcsvideos` in the NAMESPACE column for dev.

   **Optional - reproduce Priya's mistake** (on your throwaway stand-ins only):
   ```bash
   kubectl config use-context kind-lab-staging
   kubectl delete deployment web -n allcsvideos          # says "deleted from allcsvideos namespace" - not which cluster!
   kubectl config current-context                        # kind-lab-staging
   kubectl get deployment web -n allcsvideos --context kind-lab-dev   # dev is untouched: 2/2
   kubectl config use-context kind-lab
   ```

9. Who are you on this cluster?
   ```bash
   kubectl auth whoami
   kubectl auth can-i delete nodes
   kubectl auth can-i '*' '*' --all-namespaces
   ```
   You should see `Username kubernetes-admin`, `Groups [kubeadm:cluster-admins system:authenticated]`, and `yes` twice. Normal on a laptop; on shared clusters RBAC gives each person only what they need (module 18).

10. Remove the stand-ins and go back to your normal kubeconfig.
    ```bash
    kind delete cluster --name lab-dev --kubeconfig ~/.kube/dev.yaml
    kind delete cluster --name lab-staging --kubeconfig ~/.kube/staging.yaml
    unset KUBECONFIG
    rm ~/.kube/dev.yaml ~/.kube/staging.yaml
    kind get clusters
    kubectl config get-contexts
    ```
    Only `lab` is left (plus any clusters you had before).

11. The kubectl grammar: `kubectl <verb> <resource> <name> <flags>`. Find the nouns and read the built-in manual.
    ```bash
    kubectl api-resources | wc -l
    kubectl api-resources | grep -wE '^(NAME|pods|deployments|replicasets|services|namespaces|nodes|events)'
    kubectl explain deployment.spec.replicas
    kubectl get namespaces
    kubectl get pods -n kube-system
    ```
    You should see `72` lines (71 types plus a header); `po`, `svc` and `deploy` as short names; `NAMESPACED` true for pods/services/deployments and false for nodes/namespaces; `replicas <integer>` ... `Defaults to 1.`; and five namespaces: `default`, `kube-node-lease`, `kube-public`, `kube-system`, `local-path-storage`.

12. Create a namespace and generate a manifest instead of typing YAML.
    ```bash
    kubectl create namespace allcsvideos
    kubectl create deployment web --image=web:1.0 --replicas=2 -n allcsvideos --dry-run=client -o yaml > web.yaml
    cat web.yaml
    kubectl apply -f web.yaml
    kubectl rollout status deployment/web -n allcsvideos
    kubectl get pods -n allcsvideos -o wide
    ```
    `web.yaml` should match `manifests/web-2-replicas.yaml`. You should see one pod on each worker:
    ```
    NAME                   READY   STATUS    RESTARTS   AGE   IP           NODE          ...
    web-564b956f9f-dgkqj   1/1     Running   0          2s    10.244.1.2   lab-worker    ...
    web-564b956f9f-t2z5t   1/1     Running   0          2s    10.244.2.2   lab-worker2   ...
    ```

13. `create` vs `apply`, labels, and the many views of one object.
    ```bash
    kubectl create -f web.yaml
    kubectl apply -f web.yaml
    kubectl get pods -n allcsvideos -l app=web --show-labels
    kubectl describe deployment web -n allcsvideos
    kubectl get deployment web -n allcsvideos -o yaml | head -n 16
    kubectl get deployment web -n allcsvideos -o json | jq '{desired: .spec.replicas, ready: .status.readyReplicas}'
    kubectl get pods -n allcsvideos -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.nodeName}{"\n"}{end}'
    ```
    You should see `Error from server (AlreadyExists)` for `create`, `deployment.apps/web unchanged` for `apply`, labels `app=web,pod-template-hash=...`, `Replicas: 2 desired | 2 updated | 2 total | 2 available`, the `kubectl.kubernetes.io/last-applied-configuration` annotation, and `"desired": 2, "ready": 2`. (No `jq`? Skip that line.)

14. Logs and exec.
    ```bash
    kubectl logs deployment/web -n allcsvideos --tail=3
    kubectl exec -n allcsvideos deployment/web -- wget -qO- http://127.0.0.1:8080
    kubectl logs deployment/web -n allcsvideos --tail=1
    ```
    You should see:
    ```
    <h1>allcsvideos storefront</h1>
    <p>served from a kind cluster</p>
    ...
    127.0.0.1 - - [...] "GET / HTTP/1.1" 200 109 "-" "Wget" "-"
    ```

15. Make `allcsvideos` the default namespace on `kind-lab`, and turn on completion.
    ```bash
    kubectl config set-context --current --namespace=allcsvideos
    kubectl get pods
    source <(kubectl completion bash)     # zsh: source <(kubectl completion zsh)
    ```
    Type `kubectl get dep` and press Tab; type `kubectl logs web-` and press Tab twice to see real pod names.

16. The control loop. Edit `web.yaml`: change `replicas: 2` to `replicas: 4` (or `cp manifests/web-4-replicas.yaml web.yaml`). Preview, then apply while a second terminal watches with `kubectl get pods -w`.
    ```bash
    kubectl diff -f web.yaml
    kubectl apply -f web.yaml
    kubectl get deployment web
    ```
    The diff shows `-  replicas: 2` / `+  replicas: 4` and the generation going up by one. In the watch, two new pods go `Pending` -> `ContainerCreating` -> `Running` within a second; then `web 4/4`.

17. Drift: someone "fixes" things by hand. Then the file wins again.
    ```bash
    kubectl scale deployment web --replicas=6
    kubectl get deployment web
    kubectl diff -f web.yaml
    kubectl apply -f web.yaml
    kubectl get pods
    kubectl get deployment web
    ```
    The diff shows `-  replicas: 6` / `+  replicas: 4`. After apply, two pods show `Completed` for a moment (nginx exits cleanly), then `web 4/4`.

18. The cluster's diary.
    ```bash
    kubectl get events --sort-by=.lastTimestamp
    kubectl get events --sort-by=.lastTimestamp --field-selector involvedObject.kind=Deployment
    ```
    You should see:
    ```
    REASON              OBJECT           MESSAGE
    ScalingReplicaSet   deployment/web   Scaled up replica set web-564b956f9f from 0 to 2
    ScalingReplicaSet   deployment/web   Scaled up replica set web-564b956f9f from 2 to 4
    ScalingReplicaSet   deployment/web   Scaled up replica set web-564b956f9f from 4 to 6
    ScalingReplicaSet   deployment/web   Scaled down replica set web-564b956f9f from 6 to 4
    ```

19. Pitfalls, live. First, a command without `-n` on the wrong namespace:
    ```bash
    kubectl config set-context --current --namespace=default
    kubectl get pods
    kubectl delete deployment web
    kubectl get pods -n allcsvideos
    ```
    `Error from server (NotFound): deployments.apps "web" not found` - it failed safely here, but if `default` had its own `web`, that's the one you'd have deleted.

    Then editing a live object: run `kubectl edit deployment web -n allcsvideos`, change `replicas: 4` to `5`, save and quit.
    ```bash
    kubectl get deployment web -n allcsvideos
    kubectl diff -f web.yaml | grep -E '^[-+] '
    ```
    You should see `web 5/5`, then `-  replicas: 5` / `+  replicas: 4`: the next apply quietly undoes the edit.

## Common mistakes
- **Wrong context.** Show the context in your prompt, and pass `--context` in scripts so nothing depends on what happens to be current.
- **Editing live objects** with `kubectl edit` or `kubectl scale`. Git still says the old value; the next apply reverts it. Change the file, review it, apply it.
- **Not using namespaces.** Everything piles up in `default`, where every careless command lands. Give each app its own namespace.
- **`delete` without `-n`.** Always say the namespace.
- **Copying kubeconfigs around.** The file holds a client key for `kubernetes-admin` in `cluster-admins`: anyone with a copy owns the cluster. Never paste it into chat, a ticket or git; keep it mode 600.
- **Forgetting `kind load docker-image`.** A local image is not inside the kind nodes until you load it.

## Clean up
```bash
rm -f web.yaml
kind delete cluster --name lab
docker rmi web:1.0
```
If step 10 was skipped, also run `kind delete cluster --name lab-dev` / `--name lab-staging` and `unset KUBECONFIG`.
To keep the context prompt, leave `kctx`/`PS1` in your shell config; otherwise remove them.

## Next
[M13-L03 · Pods](../m13-l03-pods/)
