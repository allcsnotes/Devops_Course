# M13-L05 · Services and DNS
> Video: Module 13, Lesson 5. Watch it first, then follow along here.

## What you'll learn
- Why hard-coding a pod IP breaks on the next rollout, and how a Service gives a stable virtual IP and DNS name in front of changing pods.
- How the pieces fit: label selector, EndpointSlices (with ready flags), kube-proxy's iptables DNAT rules, conntrack, and CoreDNS.
- That a Service balances **connections**, not requests.
- Cluster DNS: `service.namespace.svc.cluster.local`, the search list, `ndots:5`, SRV records, and headless Services.
- Getting in from outside: NodePort, LoadBalancer (with MetalLB in a lab), plus ExternalName, session affinity and `port-forward`.

## Before you start
- Docker Desktop (or Docker Engine on Linux), kind **v0.33.0**, kubectl **v1.37.1**.
- Node image `kindest/node:v1.37.0` (Kubernetes 1.37.0), pinned in `kind-cluster.yaml`. Host port `127.0.0.1:30080` must be free.
- Deployments and rolling updates from [M13-L04](../m13-l04-deployments-and-replicasets/).
- Internet access from the cluster (the MetalLB manifest and the `example.com` DNS demos).

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | Cluster `lab`: one control plane, two workers; publishes `127.0.0.1:30080` -> node port 30080 |
| `app/app.py`, `app/Dockerfile` | The API: `GET /` returns JSON with version and pod name, `/whoami` the pod name, `/healthz/ready` is 503 while `/tmp/drain` exists |
| `manifests/api.yaml` | Deployment `api`: 3 replicas, named port `http` (8080), readiness probe |
| `manifests/client.yaml` | Debug pod `client` with `nicolaka/netshoot:v0.16` (curl, dig, tcpdump) |
| `manifests/storefront.yaml` | Hook: a storefront stand-in that calls a hard-coded pod IP every 2 s |
| `manifests/storefront-svc.yaml` | The fix: the same pod calling `http://api` |
| `manifests/svc.yaml` | ClusterIP Service `api`: port 80 -> targetPort `http` |
| `manifests/headless.yaml` | Headless Service `api-headless` (`clusterIP: None`) |
| `manifests/nodeport.yaml` | NodePort Service `api-public` on node port 30080 |
| `manifests/lb-pool.yaml` | MetalLB address pool `172.18.255.50-59` + L2 advertisement |
| `manifests/externalname.yaml` | ExternalName Service `payments` -> `example.com` |
| `manifests/svc-typo.yaml`, `svc-port.yaml` | Staged mistakes: wrong selector, wrong targetPort |

## Follow along

1. Create the cluster, build two API versions and load them.
   ```bash
   kind create cluster --config kind-cluster.yaml
   for v in 1.0.0 1.1.0; do docker build -q --build-arg APP_VERSION=$v -t api:$v app; done
   kind load docker-image api:1.0.0 api:1.1.0 --name lab
   ```

2. Namespace, the API and a debug pod.
   ```bash
   kubectl create namespace allcsvideos
   kubectl config set-context --current --namespace allcsvideos
   kubectl apply -f manifests/api.yaml -f manifests/client.yaml
   kubectl rollout status deploy/api
   kubectl get pods -o wide
   ```

3. **The hook: hard-code a pod IP** (Priya's mistake). The `sed` fills in the IP of the first API pod:
   ```bash
   kubectl get pods -l app=api -o wide
   IP=$(kubectl get pods -l app=api -o jsonpath='{.items[0].status.podIP}')
   sed "s/POD_IP/$IP/" manifests/storefront.yaml | kubectl apply -f -
   kubectl wait --for=condition=Ready pod/storefront && sleep 7
   kubectl logs storefront
   ```
   Every 2 s: `{"service": "api", "version": "1.0.0", "pod": "api-655745b5b6-7jwr5"}`, always the same pod. Now ship 1.1.0:
   ```bash
   kubectl set image deploy/api api=api:1.1.0
   kubectl rollout status deploy/api && sleep 6
   kubectl logs storefront --since=40s
   kubectl get pods -l app=api -o wide
   ```
   The log turns into `Could not connect to server`, then `Connection timed out`: every new pod has a new IP, and nobody owns the old one.

4. Make a Service. First see what `kubectl expose` would create, then apply the file version.
   ```bash
   kubectl expose deployment api --port 80 --target-port http --dry-run=client -o yaml
   kubectl apply -f manifests/svc.yaml
   kubectl get svc api
   kubectl describe svc api
   ```
   You should see:
   ```
   NAME   TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
   api    ClusterIP   10.96.93.217   <none>        80/TCP    2s
   ...
   Port:                     http  80/TCP
   TargetPort:               http/TCP
   Endpoints:                10.244.1.5:8080,10.244.1.4:8080,10.244.2.6:8080
   ```
   Your cluster IP and pod IPs will differ.

5. EndpointSlices: the "on shift" list.
   ```bash
   kubectl get endpointslices -l kubernetes.io/service-name=api
   kubectl get endpointslices -l kubernetes.io/service-name=api -o yaml
   kubectl get endpoints api
   ```
   Each endpoint has `ready: true, serving: true, terminating: false`, its node and a `targetRef` to its pod. The old Endpoints object prints `Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice`.

6. Watch a slice change. Terminal 2:
   ```bash
   kubectl get endpointslices -l kubernetes.io/service-name=api -w -o custom-columns='ENDPOINTS:.endpoints[*].addresses[0],READY:.endpoints[*].conditions.ready'
   ```
   Terminal 1:
   ```bash
   kubectl scale deploy/api --replicas 5
   sleep 12; kubectl get pods -l app=api -o wide
   kubectl scale deploy/api --replicas 3
   ```
   New endpoints appear with `false` and turn `true` a few seconds later (readiness); on scale-down two flip to `false` (terminating) and then disappear.

7. Readiness without scaling: make one pod "sick" (keep the watch running; use one of **your** pod names).
   ```bash
   kubectl exec <API-POD> -- touch /tmp/drain
   sleep 8; kubectl get pods -l app=api
   kubectl exec client -- sh -c 'for i in $(seq 60); do curl -s api/whoami; done | sort | uniq -c'
   kubectl exec <API-POD> -- rm /tmp/drain
   ```
   That pod goes `0/1`, its endpoint `false`, and the 60 requests are shared by the other two (24 and 36 in the video). After `rm` it's back.

8. Call the Service.
   ```bash
   kubectl exec client -- curl -s api
   kubectl exec client -- sh -c 'for i in 1 2 3 4 5 6; do curl -s api/whoami; done'
   kubectl exec client -- sh -c 'for i in $(seq 300); do curl -s api/whoami; done | sort | uniq -c'
   ```
   A random pick per connection, roughly a third each (77, 118, 105 in the video). Now one connection, five requests:
   ```bash
   kubectl exec client -- curl -s api/whoami api/whoami api/whoami api/whoami api/whoami
   kubectl exec client -- curl -s api/whoami api/whoami api/whoami api/whoami api/whoami
   ```
   All five land on one pod, the next five on another: a Service balances connections, not requests.

9. How kube-proxy does it (read-only, inside a node).
   ```bash
   kubectl -n kube-system get configmap kube-proxy -o yaml | grep "mode:"
   kubectl -n kube-system logs ds/kube-proxy | grep Proxier
   kubectl -n kube-system exec ds/kube-proxy -- kube-proxy --help | grep -o "on Linux this can be.*nftables'."
   docker exec lab-worker iptables-save -t nat | grep 'KUBE-SERVICES.*allcsvideos/api'
   ```
   Copy the `KUBE-SVC-...` chain name from the last line, then:
   ```bash
   docker exec lab-worker iptables-save -t nat | grep -- '-A KUBE-SVC-<YOUR-CHAIN>'
   docker exec lab-worker iptables-save -t nat | grep -- '-A KUBE-SEP.*allcsvideos.*DNAT'
   ```
   You should see `mode: iptables`, rules with `--probability 0.33333333349`, then `0.50000000000`, then a last one with no probability, and one `DNAT --to-destination <pod-ip>:8080` per endpoint.

10. The connection memory: conntrack. Find the client's node, call from a fixed source port, and ask conntrack on **that** node:
    ```bash
    kubectl get pod client -o wide
    kubectl exec client -- curl -s --local-port 40000 api/whoami
    docker exec <CLIENT-NODE> conntrack -L -p tcp --sport 40000
    ```
    One entry: `src=<client-ip> dst=<cluster-ip> sport=40000 dport=80 src=<pod-ip> ... sport=8080`. (Wait a minute before repeating, or use another port: the old entry lingers in `TIME_WAIT`.)

11. DNS.
    ```bash
    kubectl exec client -- cat /etc/resolv.conf
    kubectl -n kube-system get svc kube-dns
    kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
    kubectl -n kube-system get configmap coredns -o jsonpath="{.data.Corefile}"
    ```
    You should see:
    ```
    search allcsvideos.svc.cluster.local svc.cluster.local cluster.local
    nameserver 10.96.0.10
    options ndots:5
    ```
    Now resolve names:
    ```bash
    kubectl exec client -- dig +short api.allcsvideos.svc.cluster.local
    kubectl exec client -- dig +short api
    kubectl exec client -- dig +search +short api
    kubectl exec client -- dig +search +short api.allcsvideos
    kubectl exec client -- curl -s api.allcsvideos.svc.cluster.local/whoami
    ```
    The full name returns the cluster IP; plain `dig api` returns nothing (dig ignores the search list); with `+search` both short names work.

12. Across namespaces, and SRV records.
    ```bash
    kubectl create namespace ops
    kubectl -n ops run probe --image nicolaka/netshoot:v0.16 -- sleep infinity
    kubectl -n ops wait --for=condition=Ready pod/probe
    kubectl -n ops exec probe -- grep search /etc/resolv.conf
    kubectl -n ops exec probe -- curl -sS api/whoami
    kubectl -n ops exec probe -- curl -sS api.allcsvideos/whoami
    kubectl exec client -- dig +short SRV _http._tcp.api.allcsvideos.svc.cluster.local
    ```
    From `ops`: `Could not resolve host: api`, but `api.allcsvideos` works. The SRV answer: `0 100 80 api.allcsvideos.svc.cluster.local.`

13. The `ndots:5` surprise, seen with tcpdump.
    ```bash
    kubectl exec client -- sh -c 'tcpdump -i eth0 -n -l udp port 53 2>/dev/null & sleep 1; curl -s -o /dev/null -w "HTTP %{http_code}\n" http://example.com; sleep 1; kill %1' | grep -E 'A\?|HTTP'
    kubectl exec client -- sh -c 'tcpdump -i eth0 -n -l udp port 53 2>/dev/null & sleep 1; curl -s -o /dev/null -w "HTTP %{http_code}\n" http://example.com./; sleep 1; kill %1' | grep -E 'A\?|HTTP'
    ```
    First: eight queries (`example.com.allcsvideos.svc.cluster.local`, `example.com.svc.cluster.local`, `example.com.cluster.local`, then `example.com`, each A and AAAA). With the trailing dot: two.

14. A headless Service.
    ```bash
    kubectl apply -f manifests/headless.yaml
    kubectl get svc
    kubectl exec client -- dig +search +short api-headless
    kubectl get pods -l app=api -o wide
    kubectl exec client -- dig +short SRV _http._tcp.api-headless.allcsvideos.svc.cluster.local
    ```
    `CLUSTER-IP None`; DNS returns the three pod IPs; SRV lists each pod, like `0 33 8080 10-244-1-4.api-headless.allcsvideos.svc.cluster.local.`

15. NodePort: in from your laptop.
    ```bash
    kubectl apply -f manifests/nodeport.yaml
    kubectl get svc api-public
    curl -s 127.0.0.1:30080
    curl -s 127.0.0.1:30080
    ```
    `api-public NodePort ... 80:30080/TCP`, and two answers, often from two pods. Open http://127.0.0.1:30080 in your browser too. Any node answers, even the control plane, which runs no API pods. Node IPs are on the `kind` Docker network, which your Mac/Windows host can't reach directly, so ask from a throwaway container on that network:
    ```bash
    kubectl get nodes -o custom-columns=NAME:.metadata.name,IP:.status.addresses[0].address
    docker run --rm --network kind curlimages/curl:8.11.1 -s <NODE-IP>:30080/whoami
    docker exec lab-worker iptables-save -t nat | grep -- '-A KUBE-NODEPORTS'
    kubectl create service nodeport test --tcp 80:8080 --node-port 29999
    ```
    The last command fails: `29999: provided port is not in the valid range` (30000-32767).

16. LoadBalancer: pending without a cloud, then MetalLB plays the cloud.
    ```bash
    kubectl expose deployment api --name api-lb --type LoadBalancer --port 80 --target-port http
    kubectl get svc api-lb
    sleep 60; kubectl get svc api-lb
    ```
    `EXTERNAL-IP <pending>`, still after 60 s, plus a node port like `80:31731/TCP`. Install MetalLB v0.16.0 and give it a pool (check `docker network inspect kind` first: the pool must be inside that subnet; edit `manifests/lb-pool.yaml` if yours isn't 172.18.0.0/16):
    ```bash
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.0/config/manifests/metallb-native.yaml | tail -3
    kubectl -n metallb-system wait --for=condition=Ready pod --all --timeout=180s
    kubectl apply -f manifests/lb-pool.yaml
    sleep 3; kubectl get svc api-lb
    docker run --rm --network kind curlimages/curl:8.11.1 -s 172.18.255.50
    kubectl describe svc api-lb | tail -4
    ```
    `EXTERNAL-IP 172.18.255.50`, a JSON answer, and events `IPAllocated` from metallb-controller and `nodeAssigned ... announcing from node "lab-worker" with protocol "layer2"`. On Linux you can also `curl 172.18.255.50` directly; macOS and Windows don't route to the kind network.

17. ExternalName, session affinity, port-forward.
    ```bash
    kubectl apply -f manifests/externalname.yaml
    kubectl get svc payments
    kubectl exec client -- dig +search payments | grep -A3 "ANSWER SECTION"
    kubectl patch svc api -p '{"spec":{"sessionAffinity":"ClientIP"}}'
    kubectl get svc api -o jsonpath="{.spec.sessionAffinityConfig}{\"\n\"}"
    kubectl exec client -- sh -c 'for i in $(seq 60); do curl -s api/whoami; done | sort | uniq -c'
    kubectl patch svc api -p '{"spec":{"sessionAffinity":"None"}}'
    ```
    `payments` is a CNAME to `example.com.`; with ClientIP affinity (`"timeoutSeconds":10800`) all 60 requests hit one pod. Then, in terminal 2: `kubectl port-forward svc/api 8080:80`. In terminal 1:
    ```bash
    curl -s 127.0.0.1:8080
    curl -s 127.0.0.1:8080/whoami
    curl -s 127.0.0.1:8080/whoami
    ```
    All to the same pod: port-forward picks one pod and sticks to it. Stop it with Ctrl+C.

18. Fix the storefront: call the Service name. Put the API back on 1.0.0 first, then roll out 1.1.0 again.
    ```bash
    kubectl set image deploy/api api=api:1.0.0 && kubectl rollout status deploy/api
    kubectl delete pod storefront
    kubectl apply -f manifests/storefront-svc.yaml
    kubectl wait --for=condition=Ready pod/storefront && sleep 4
    kubectl set image deploy/api api=api:1.1.0
    kubectl rollout status deploy/api && sleep 4
    kubectl logs storefront
    ```
    Answers from 1.0.0 pods, a mix during the rollout, then only 1.1.0 - and not a single error.

19. Staged mistakes.
    ```bash
    kubectl apply -f manifests/svc-typo.yaml
    kubectl get endpointslices -l kubernetes.io/service-name=api-v2
    kubectl exec client -- curl -sS -m 3 api-v2
    kubectl describe svc api-v2 | grep -E "Selector|Endpoints"
    kubectl get pods --show-labels
    docker exec lab-worker2 iptables-save | grep 'api-v2'
    kubectl apply -f manifests/svc-port.yaml
    kubectl get endpointslices -l kubernetes.io/service-name=api-v3
    kubectl exec client -- curl -sS -m 3 api-v3
    kubectl get svc -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type | grep -E 'NodePort|LoadBalancer|TYPE'
    ```
    `api-v2`: empty slice (`<unset>`), `Could not connect to server`, `Selector: app=api-server` vs pods labelled `app=api`, and a `REJECT` rule `"allcsvideos/api-v2 has no endpoints"`. `api-v3`: endpoints look fine (port 80) but curl still fails - the app listens on 8080. The last command audits what is exposed outside the cluster.

## Common mistakes
- **A selector that doesn't match.** Empty endpoints almost always mean a label mismatch or no ready pods. Compare `Selector` in `describe` with `kubectl get pods --show-labels`.
- **`port` vs `targetPort`.** `port` is what clients call; `targetPort` is what the container listens on. Use named ports so they can't drift apart.
- **Hard-coding pod IPs.** They change with every rollout, reschedule and replacement. Always call the Service name.
- **ndots surprises.** Every external name costs extra lookups. Use trailing dots or tune `dnsConfig` for busy external callers.
- **Exposing internal services.** A NodePort or LoadBalancer on an internal API or database opens it to anyone who can reach a node. Audit with `kubectl get svc -A`; expose only the front door.

## Clean up
```bash
kind delete cluster --name lab
docker rmi api:1.0.0 api:1.1.0
```
(Deleting the cluster also removes MetalLB, the `ops` namespace and every Service.)

## Next
[M13-L06 · ConfigMaps and Secrets](../m13-l06-configmaps-and-secrets/)
