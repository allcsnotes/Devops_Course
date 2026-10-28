# M13-L01 · Why Orchestration
> Video: Module 13, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- What Docker and Compose can't do: they run containers on one host, so a dead server takes everything with it.
- The seven jobs of an orchestrator: scheduling, self-healing, scaling, rolling updates, service discovery and load balancing, configuration and secrets, and declarative desired state.
- How Kubernetes is built: the control plane (kube-apiserver, etcd, kube-scheduler, kube-controller-manager) and the nodes (kubelet, containerd through CRI, kube-proxy), plus add-ons like CoreDNS and a network plugin.
- What really happens when you run `kubectl create deployment`, step by step.
- The control loop in action: a deleted pod comes back in the same second; a dead node's pods move after five minutes.

## Before you start
- Docker Desktop (or Docker Engine on Linux), running.
- kind **v0.33.0**: https://kind.sigs.k8s.io/docs/user/quick-start/#installation (check with `kind version`).
- kubectl **v1.37.1**: https://kubernetes.io/docs/tasks/tools/ (check with `kubectl version --client`).
- The cluster uses the node image `kindest/node:v1.37.0` (Kubernetes 1.37.0), pinned in `kind-cluster.yaml`.
- About 3 GB of free memory for Docker. No earlier lesson folder is needed.

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | kind config: cluster `lab`, one control-plane node and two workers, pinned node image |

## Follow along

1. Check your tools and look at the cluster config.
   ```bash
   kind version
   kubectl version --client
   cat kind-cluster.yaml
   kind get clusters
   ```
   You should see:
   ```
   kind v0.33.0 go1.26.7 linux/arm64
   Client Version: v1.37.1
   ...
   No kind clusters found.
   ```
   (`darwin/arm64`, `linux/amd64` etc. depending on your machine.)

2. Create the cluster. In the video it took 31 seconds.
   ```bash
   time kind create cluster --config kind-cluster.yaml
   ```
   You should see:
   ```
   Creating cluster "lab" ...
    ✓ Ensuring node image (kindest/node:v1.37.0) 🖼️
    ✓ Preparing nodes 📦 📦 📦
    ✓ Writing configuration 📜
    ✓ Starting control-plane 🕹️
    ✓ Installing CNI 🔌
    ✓ Installing StorageClass 💾
    ✓ Joining worker nodes 🚜
   Set kubectl context to "kind-lab"
   ```

3. Every node is just a Docker container. The control plane publishes the API server (port 6443) on a random local port.
   ```bash
   docker ps --filter label=io.x-k8s.kind.cluster=lab --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
   ```
   You should see:
   ```
   NAMES               IMAGE                  STATUS          PORTS
   lab-control-plane   kindest/node:v1.37.0   Up 31 seconds   127.0.0.1:56397->6443/tcp
   lab-worker          kindest/node:v1.37.0   Up 31 seconds
   lab-worker2         kindest/node:v1.37.0   Up 31 seconds
   ```
   Your port number (56397 here), ages and IP addresses will be different. That's fine everywhere in this lesson.

4. Look at the nodes. Right after the create, workers can say `NotReady` while the network plugin starts; wait a few seconds and run it again.
   ```bash
   kubectl get nodes
   kubectl get nodes -o wide
   ```
   You should see:
   ```
   NAME                STATUS   ROLES           AGE   VERSION   INTERNAL-IP   ...   OS-IMAGE                       ...   CONTAINER-RUNTIME
   lab-control-plane   Ready    control-plane   44s   v1.37.0   172.18.0.4    ...   Debian GNU/Linux 13 (trixie)   ...   containerd://2.3.4
   lab-worker          Ready    <none>          28s   v1.37.0   172.18.0.2    ...   Debian GNU/Linux 13 (trixie)   ...   containerd://2.3.4
   lab-worker2         Ready    <none>          28s   v1.37.0   172.18.0.3    ...   Debian GNU/Linux 13 (trixie)   ...   containerd://2.3.4
   ```

5. Find the API server, the cluster's front door.
   ```bash
   kubectl cluster-info
   ```
   You should see:
   ```
   Kubernetes control plane is running at https://127.0.0.1:56397
   CoreDNS is running at https://127.0.0.1:56397/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
   ```

6. See the architecture running as pods in the `kube-system` namespace.
   ```bash
   kubectl get pods -n kube-system -o wide
   ```
   You should see one each of `etcd-lab-control-plane`, `kube-apiserver-lab-control-plane`, `kube-controller-manager-lab-control-plane` and `kube-scheduler-lab-control-plane`, a `kube-proxy-...` and a `kindnet-...` pod on every node, and two `coredns-...` pods. There is no cloud-controller-manager: a local cluster has no cloud.

7. Look inside the control-plane node. It's a container, so `docker exec` gets you in (on a real server you'd use SSH). `crictl` talks to containerd over CRI.
   ```bash
   docker exec lab-control-plane crictl ps
   docker exec lab-control-plane systemctl is-active containerd kubelet
   docker exec lab-control-plane ls /etc/kubernetes/manifests
   ```
   You should see the control-plane components as containers, then:
   ```
   active
   active
   etcd.yaml
   kube-apiserver.yaml
   kube-controller-manager.yaml
   kube-scheduler.yaml
   ```
   containerd and the kubelet are ordinary system services, not pods. The kubelet starts the control plane from those four files: these are **static pods**.

8. Talk to the API directly. kubectl is just an HTTPS client.
   ```bash
   kubectl get --raw /healthz; echo
   kubectl get --raw '/readyz?verbose' | tail -4
   kubectl -v=6 get pods
   ```
   You should see:
   ```
   ok
   ...
   [+]shutdown ok
   readyz check passed
   ...
   "Response" verb="GET" url="https://127.0.0.1:56397/api/v1/namespaces/default/pods?limit=500" status="200 OK" milliseconds=10
   No resources found in default namespace.
   ```

9. Create a Deployment: nginx 1.29.8 on Alpine, three replicas.
   ```bash
   kubectl create deployment web --image=nginx:1.29.8-alpine --replicas=3
   kubectl rollout status deployment/web
   kubectl get pods -o wide
   kubectl get deployment,replicaset
   ```
   You should see:
   ```
   deployment.apps/web created
   Waiting for deployment "web" rollout to finish: 0 of 3 updated replicas are available...
   ...
   deployment "web" successfully rolled out
   NAME                   READY   STATUS    RESTARTS   AGE   IP           NODE          ...
   web-7f79c98dcd-j5944   1/1     Running   0          11s   10.244.2.2   lab-worker    ...
   web-7f79c98dcd-jz2bv   1/1     Running   0          11s   10.244.2.3   lab-worker    ...
   web-7f79c98dcd-q7lvw   1/1     Running   0          11s   10.244.1.2   lab-worker2   ...

   NAME                             DESIRED   CURRENT   READY   AGE
   replicaset.apps/web-7f79c98dcd   3         3         3       12s
   ```
   No pod lands on the control plane. Check why:
   ```bash
   kubectl describe node lab-control-plane | grep -A1 Taints
   ```
   ```
   Taints:             node-role.kubernetes.io/control-plane:NoSchedule
   ```

10. Every component leaves events with its name on them. This is the chain from the animation.
    ```bash
    kubectl events --types=Normal
    kubectl get events --field-selector involvedObject.kind!=Node --sort-by=.metadata.creationTimestamp -o custom-columns=FROM:.source.component,REASON:.reason,OBJECT:.involvedObject.name
    ```
    You should see:
    ```
    FROM                    REASON              OBJECT
    replicaset-controller   SuccessfulCreate    web-7f79c98dcd
    default-scheduler       Scheduled           web-7f79c98dcd-q7lvw
    deployment-controller   ScalingReplicaSet   web
    ...
    kubelet                 Pulling             web-7f79c98dcd-jz2bv
    kubelet                 Pulled              web-7f79c98dcd-q7lvw
    kubelet                 Created             web-7f79c98dcd-q7lvw
    kubelet                 Started             web-7f79c98dcd-q7lvw
    ```

11. Break it on purpose: delete a pod. Use two terminals. In terminal 1, watch the pods:
    ```bash
    kubectl get pods -o wide -w
    ```
    In terminal 2, delete one of **your** pod names (copy it from `kubectl get pods`):
    ```bash
    date +%T; kubectl delete pod web-7f79c98dcd-j5944
    ```
    In terminal 1 you should see, in the same second, the old pod `Terminating` and a new one going `Pending` -> `ContainerCreating` -> `Running`. Stop the watch with Ctrl+C, then:
    ```bash
    kubectl get pods -o wide
    ```
    Three of three again. Nobody told Kubernetes to restart anything: the ReplicaSet controller saw two where three were wanted.
    Tip: on macOS/Linux with `moreutils` installed you can add a timestamp to every watch line: `kubectl get pods -o wide -w | ts '%H:%M:%S'`.

12. Now a whole machine dies. This takes about **six minutes**. Terminal 1: `kubectl get pods -o wide -w`. Optional terminal 3: `kubectl get nodes -w`. Terminal 2:
    ```bash
    date +%T; docker stop lab-worker2
    kubectl get nodes
    ```
    Right afterwards the node still says `Ready`: the control plane doesn't know yet. After about 40-50 seconds (node monitor grace period, 50 s by default):
    ```bash
    date +%T; kubectl get nodes
    kubectl describe node lab-worker2 | grep -A2 Taints
    kubectl get pods -o wide
    ```
    You should see:
    ```
    lab-worker2         NotReady   <none>          3m7s    v1.37.0
    Taints:             node.kubernetes.io/unreachable:NoExecute
                        node.kubernetes.io/unreachable:NoSchedule
    ```
    The pods on worker2 still say `Running`: that's the last status its kubelet reported. Why aren't they moved? Look at the tolerations every pod gets automatically (use a pod name from worker2):
    ```bash
    kubectl get pod web-7f79c98dcd-q7lvw -o jsonpath='{.spec.tolerations}'; echo
    ```
    You should see `node.kubernetes.io/not-ready` and `node.kubernetes.io/unreachable`, both `NoExecute` with `"tolerationSeconds":300`. (Pipe through `jq .` if you have it, for pretty output.)

13. Wait five minutes after `NotReady`. Then:
    ```bash
    date +%T; kubectl get pods -o wide
    kubectl get deployment web
    ```
    You should see:
    ```
    web-7f79c98dcd-7gzfm   1/1     Terminating   0          6m47s   10.244.1.3   lab-worker2   ...
    web-7f79c98dcd-jz2bv   1/1     Running       0          7m22s   10.244.2.3   lab-worker    ...
    web-7f79c98dcd-q7lvw   1/1     Terminating   0          7m22s   10.244.1.2   lab-worker2   ...
    web-7f79c98dcd-xmcqq   1/1     Running       0          37s     10.244.2.5   lab-worker    ...
    web-7f79c98dcd-xnckn   1/1     Running       0          37s     10.244.2.4   lab-worker    ...
    NAME   READY   UP-TO-DATE   AVAILABLE   AGE
    web    3/3     3            3           7m23s
    ```
    The old pods stay `Terminating` because only the kubelet on worker2 can confirm they've stopped.

14. Bring the machine back.
    ```bash
    date +%T; docker start lab-worker2
    kubectl get nodes
    kubectl get pods -o wide
    ```
    A few seconds later worker2 is `Ready`, the two old pods are gone, and all three pods run on `lab-worker`. Kubernetes doesn't move running pods back to rebalance.

15. Desired vs actual state, right in the object:
    ```bash
    kubectl get deployment web -o yaml | grep -E '^  replicas:|^  readyReplicas:|^spec:|^status:'
    ```
    You should see:
    ```
    spec:
      replicas: 3
    status:
      readyReplicas: 3
      replicas: 3
    ```

## Common mistakes
- **Treating Kubernetes like a VM manager.** Pods are replaced, not repaired. Never SSH or `exec` in to patch one: change the image or the spec.
- **Running Kubernetes for a one-container app.** You pay for a control plane, upgrades and YAML to run what one server would run.
- **Ignoring control-plane high availability.** This lab has one control-plane node and one etcd. Production runs three or five so etcd keeps a majority. If the control plane is down, running pods keep running, but nothing heals, scales or deploys.
- **Using kind in production.** All its nodes are containers on one machine. kind is for learning and CI.

## Clean up
```bash
kind delete cluster --name lab
kind get clusters
```
You should see `Deleted nodes: ["lab-control-plane" "lab-worker" "lab-worker2"]` and then `No kind clusters found.` (if you have no other kind clusters).

## Next
[M13-L02 · Your First Cluster](../m13-l02-your-first-cluster/)
