# M18-L04 · Kubernetes Security
> Video: Module 18, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- The path of a request: authentication (who), RBAC authorization (what), admission, then etcd; and the packet path with NetworkPolicies.
- Finding and fixing an over-broad RBAC binding with `kubectl auth can-i`, least-privilege Roles, and no automounted token.
- Default-deny network policies per namespace, then allowing each path on both ends, DNS included.
- Pod Security Standards (privileged, baseline, restricted) with Pod Security Admission: warn, audit, enforce.
- Kyverno 1.19 CEL policies (ValidatingPolicy, ImageValidatingPolicy): Audit, reports, scoping, Deny, and only signed images.

## Before you start
- Docker Desktop with about 4 GB free memory. Everything else (kind, kubectl, helm, cosign) runs in the lab tool box.
- Kubernetes basics from Module 13, NetworkPolicies from Module 14, and cosign signing from [M18-L03](../m18-l03-supply-chain-security/).
- Free port 5001 (the lab registry on your laptop).
- Pinned versions: `kindest/node:v1.35.8` (by digest; Kyverno 1.19 supports Kubernetes 1.33 to 1.35), kind v0.33.0,
  kubectl v1.35.9, helm v4.3.1, cosign v3.1.4, Kyverno chart 3.9.2 (Kyverno 1.19.2), `registry:3.1.2`, `alpine:3.23.6`.

## Files in this folder
| File | What it is |
|---|---|
| `lab/lab.sh` | `up` (tool box, registry, cluster `k8s-sec`, the 1.0 images), `sh`, `sync`, `down` |
| `lab/Dockerfile`, `lab/kind-cluster.yaml` | The tool box image (checksum-verified binaries) and the one-node kind cluster that can pull from `registry.lab:5000` |
| `app/Dockerfile` | One tiny HTTP service image for catalog and api, with curl, jq and pg_isready |
| `manifests/base/` | Namespaces `catalog`, `api`, `data`; the catalog, api and PostgreSQL (fake password) deployments |
| `manifests/staged/ops-debug.yaml` | STAGED: the over-broad ClusterRoleBinding from the hook |
| `manifests/rbac/` | Least privilege: a Role for one ConfigMap, and the service account with `automountServiceAccountToken: false` |
| `manifests/netpol/` | `default-deny`, `db-from-api`, `api-egress` (DNS + 5432), `api-from-catalog` |
| `manifests/psa/` | `debug-root.yaml` (a staged pod that asks for everything) and `catalog-secure.yaml` (the restricted catalog) |
| `manifests/kyverno/` | `require-labels`, `disallow-latest-tag` (Deny), `require-limits` (Audit) |
| `manifests/kyverno-scoped/` | The same three, excluding system namespaces, with `require-limits` on Deny |
| `manifests/images/verify-allcs-images.tpl` | The ImageValidatingPolicy; you insert your own `cosign.pub` (step 13) |

## Follow along
1. Start the lab (several minutes the first time) and open the tool box shell. All commands below run in it.
   ```bash
   cd lab
   ./lab.sh up
   ./lab.sh sh
   ```
2. **The hook.** Deploy the services and the staged binding, then ask what the catalog's service account can do.
   ```bash
   kubectl apply -f base/namespaces.yaml
   kubectl apply -f base/
   kubectl apply -f staged/ops-debug.yaml
   kubectl get pods -A -l team
   kubectl auth can-i list secrets --all-namespaces --as=system:serviceaccount:catalog:catalog
   kubectl auth can-i get secrets -n data --as=system:serviceaccount:catalog:catalog
   kubectl get clusterrolebinding ops-debug -o wide
   kubectl exec -n catalog deploy/catalog -- pg_isready -h db.data -t 3
   ```
   `yes`, `yes`, and `db.data:5432 - accepting connections`.
3. **Who am I?**
   ```bash
   kubectl auth whoami
   kubectl auth whoami --as=system:serviceaccount:catalog:catalog
   kubectl get secrets -n data --as=system:serviceaccount:api:api
   ```
   `kubernetes-admin` in `kubeadm:cluster-admins`; the service account's groups; and
   `Error from server (Forbidden): ... cannot list resource "secrets" ... in the namespace "data"`.
4. **RBAC: least privilege.**
   ```bash
   kubectl auth can-i --list -n data --as=system:serviceaccount:catalog:catalog
   kubectl delete clusterrolebinding ops-debug
   kubectl apply -f rbac/catalog-rbac.yaml
   SA=system:serviceaccount:catalog:catalog
   kubectl auth can-i list secrets --all-namespaces --as=$SA
   kubectl auth can-i get secrets -n data --as=$SA
   kubectl auth can-i get configmap/catalog-config -n catalog --as=$SA
   kubectl auth can-i get configmap/other -n catalog --as=$SA
   ```
   Before: `secrets [get list watch]`. After: `no`, `no`, `yes`, `no`.
5. **No token where none is needed.**
   ```bash
   kubectl exec -n catalog deploy/catalog -- ls /var/run/secrets/kubernetes.io/serviceaccount
   kubectl apply -f rbac/catalog-sa.yaml
   kubectl rollout restart deploy/catalog -n catalog
   kubectl rollout status deploy/catalog -n catalog --timeout=180s
   kubectl exec -n catalog deploy/catalog -- ls /var/run/secrets/kubernetes.io/serviceaccount
   ```
   `ca.crt namespace token`, then `No such file or directory`.
6. **Network policies.** Set two shortcuts, look before, then default deny in `data`.
   ```bash
   CAT='kubectl exec -n catalog deploy/catalog --'; API='kubectl exec -n api deploy/api --'
   $CAT pg_isready -h db.data -t 3
   $CAT curl -s --connect-timeout 3 api.api:8080; echo
   kubectl get networkpolicy -A
   kubectl apply -n data -f netpol/default-deny.yaml
   $CAT pg_isready -h db.data -t 3
   $API pg_isready -h db.data -t 3
   ```
   Both now `no response` (exit code 2). Open one door:
   ```bash
   kubectl apply -f netpol/db-from-api.yaml
   $API pg_isready -h db.data -t 3
   $CAT pg_isready -h db.data -t 3
   ```
   The api: `accepting connections`; the catalog: still `no response`.
7. **Both ends, and DNS.** Default deny in `api` too, and the api is cut off again: its egress (and DNS) is closed.
   ```bash
   kubectl apply -n api -f netpol/default-deny.yaml
   $API pg_isready -h db.data -t 3
   $API curl -sS --connect-timeout 3 http://db.data:5432; echo "exit code: $?"
   kubectl apply -f netpol/api-egress.yaml
   $API pg_isready -h db.data -t 3
   ```
   `curl: (28) Resolving timed out after 3001 milliseconds`: the name never became an address. After `api-egress`
   (DNS to CoreDNS + 5432 to db): `accepting connections`.
8. **The api's front door.**
   ```bash
   $CAT curl -s --connect-timeout 3 api.api:8080; echo "exit code: $?"
   kubectl apply -f netpol/api-from-catalog.yaml
   $CAT curl -s --connect-timeout 3 api.api:8080; echo
   kubectl get networkpolicy -A
   ```
   Exit code 28, then `{"service":"api","version":"1.0"}`, and five policies in two namespaces.
9. **Pod Security Admission: warn first.**
   ```bash
   kubectl label ns catalog pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/audit=restricted
   kubectl apply -f psa/debug-root.yaml
   kubectl delete pod debug-root -n catalog --wait=false
   kubectl label --dry-run=server --overwrite ns catalog pod-security.kubernetes.io/enforce=restricted
   ```
   A warning lists every violation, and still `pod/debug-root created`. The dry run names the running catalog pod:
   `allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile`.
10. **Enforce, then fix the catalog.**
    ```bash
    kubectl label ns catalog pod-security.kubernetes.io/enforce=restricted
    kubectl apply -f psa/debug-root.yaml
    kubectl apply -f psa/catalog-secure.yaml
    kubectl rollout status deploy/catalog -n catalog --timeout=180s
    $CAT id
    $CAT touch /srv/x
    $CAT curl -s --connect-timeout 3 api.api:8080; echo
    kubectl label ns data pod-security.kubernetes.io/enforce=baseline pod-security.kubernetes.io/warn=restricted
    kubectl get ns catalog api data -L pod-security.kubernetes.io/enforce,pod-security.kubernetes.io/warn
    ```
    `Forbidden: violates PodSecurity "restricted:latest"`, then `uid=10001(app)`, `Read-only file system`, and the
    api still answers. PostgreSQL needs root at startup, so `data` enforces baseline.
11. **Kyverno.** Install, look at the default webhook exclusions, apply the three policies.
    ```bash
    helm repo add kyverno https://kyverno.github.io/kyverno/
    helm install kyverno kyverno/kyverno --version 3.9.2 -n kyverno --create-namespace --wait --timeout 10m | head -6
    kubectl get pods -n kyverno
    helm show values kyverno/kyverno --version 3.9.2 | grep -A7 "^  webhooks:"
    kubectl apply -f kyverno/
    kubectl get validatingpolicies
    kubectl run quick-test -n api --image=nginx:latest
    kubectl create deployment quick -n api --image=registry.lab:5000/allcs/api:1.0
    ```
    Four controllers; then both are denied: `use a fixed image tag, not latest (or no tag)` and
    `pods need the labels app and team` (Kyverno generates the same rule for Deployments).
12. **Audit, then scope and enforce.** Wait about 40 seconds for reports.
    ```bash
    kubectl get policyreports -n api
    kubectl get policyreports -n api -o json | jq -r '.items[] | select(.scope.kind=="Pod") | .results[] | [.policy, .result, .message] | @tsv'
    kubectl get policyreports -n kube-system | head -5
    kubectl apply -f kyverno-scoped/
    kubectl set resources deploy/api -n api --requests=cpu=50m,memory=32Mi --limits=cpu=200m,memory=64Mi
    kubectl set resources deploy/db -n data --requests=cpu=100m,memory=128Mi --limits=cpu=500m,memory=256Mi
    kubectl rollout status deploy/api -n api --timeout=180s && kubectl rollout status deploy/db -n data --timeout=180s
    kubectl run nolimits -n api --image=registry.lab:5000/allcs/api:1.0 --labels=app=nolimits,team=platform
    kubectl get policyreports -A | grep -E "NAMESPACE|Pod "
    ```
    `require-limits fail every container needs CPU and memory limits`; kube-system pods fail 2 of 3 rules (the
    webhook skips them, the policies don't). After scoping: the new pod is denied, and api, catalog and db pods show 3 passes.
13. **Only signed images.** Build 1.1 (the release) and 1.1-hotfix (built by hand), sign only 1.1, by digest. The key
    password is a **fake** lab value. This lab uses cosign's classic signature format, because Kyverno 1.19.2 fetched the
    new bundle format over HTTPS and the lab registry is plain HTTP.
    ```bash
    docker build -q -t localhost:5001/allcs/catalog:1.1 --build-arg VERSION=1.1 app
    docker build -q -t localhost:5001/allcs/catalog:1.1-hotfix --build-arg VERSION=1.1-hotfix app
    docker push -q localhost:5001/allcs/catalog:1.1 && docker push -q localhost:5001/allcs/catalog:1.1-hotfix
    export COSIGN_PASSWORD='FAKE-lab-only-m18l04'
    cosign generate-key-pair
    IMG=$(docker inspect --format "{{index .RepoDigests 0}}" localhost:5001/allcs/catalog:1.1); echo $IMG
    cosign sign --key cosign.key --new-bundle-format=false --use-signing-config=false --tlog-upload=false --allow-http-registry -y $IMG
    cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry localhost:5001/allcs/catalog:1.1 > /dev/null; echo "exit code: $?"
    cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry localhost:5001/allcs/catalog:1.1-hotfix > /dev/null; echo "exit code: $?"
    ```
    `exit code: 0`, then `no signatures found` and `exit code: 10`. Put your public key into the policy and apply it:
    ```bash
    awk '/PUBKEY/{while((getline l < "cosign.pub")>0) print "          " l; next} {print}' images/verify-allcs-images.tpl > images/verify-allcs-images.yaml
    kubectl apply -f images/verify-allcs-images.yaml
    kubectl get imagevalidatingpolicies
    kubectl set image deploy/catalog -n catalog catalog=registry.lab:5000/allcs/catalog:1.1-hotfix
    kubectl set image deploy/catalog -n catalog catalog=registry.lab:5000/allcs/catalog:1.1
    kubectl rollout status deploy/catalog -n catalog --timeout=180s
    kubectl get pods -n catalog -o jsonpath="{.items[*].spec.containers[0].image}"; echo
    kubectl exec -n catalog deploy/catalog -- curl -s localhost:8080; echo
    ```
    The hotfix: `denied ... Policy verify-allcs-images failed: allcs images must be signed by the CI key`. The signed
    1.1 rolls out, and Kyverno pinned it to the verified digest: `registry.lab:5000/allcs/catalog:1.1@sha256:...`,
    `{"service":"catalog","version":"1.1"}`.
14. The webhook fails closed: if Kyverno is down, matching requests are rejected.
    ```bash
    kubectl get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg -o jsonpath='{range .webhooks[*]}{.name}{"  "}{.failurePolicy}{"\n"}{end}'
    ```

## Common mistakes
- **cluster-admin for CI.** Give a pipeline a Role in its app's namespace, or use GitOps so CI holds no cluster keys.
- **Wildcard verbs and resources, and "temporary" bindings.** Review them with `auth can-i` on a schedule.
- **Default deny without egress for DNS.** Everything times out; "Resolving timed out" is the clue.
- **Pod Security in warn mode forever.** Set a date, fix the warnings, then enforce.
- **Policies that block kube-system.** Exclude system namespaces, start in Audit, and remember the webhook fails closed.

## Clean up
On your laptop, in `lab/`:
```bash
./lab.sh down
```

## Next
[M18-L05 · Cloud Security and Compliance](../m18-l05-cloud-security-and-compliance/)
