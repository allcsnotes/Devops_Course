# M13-L06 · ConfigMaps and Secrets
> Video: Module 13, Lesson 6. Watch it first, then follow along here.

## What you'll learn
- Why settings must not be baked into the image (build once, deploy many), and the four ways to create a ConfigMap.
- How pods consume config: env vars (read once at start) vs mounted files (updated in about a minute), and the `subPath` trap.
- How to roll out config changes: `rollout restart`, the checksum annotation, and immutable ConfigMaps with versioned names.
- Secrets: types, `data` vs `stringData`, and why base64 is not encryption - the password sits in plain bytes in etcd.
- Encryption at rest with an `EncryptionConfiguration` (secretbox), and rewriting old Secrets.
- Files vs env vars for credentials, projected volumes, and the RBAC surprises: pod creation and `list` both reveal Secrets.

## Before you start
- Docker Desktop (or Docker Engine on Linux), kind **v0.33.0**, kubectl **v1.37.1**, `jq`, `openssl`.
- Node image `kindest/node:v1.37.0` (Kubernetes 1.37.0), pinned in `kind-cluster.yaml`.
- A bash shell (macOS, Linux, or WSL on Windows). `hexdump` and `sha256sum` (on macOS use `shasum -a 256` instead of `sha256sum`).
- Deployments and rollouts from [M13-L04](../m13-l04-deployments-and-replicasets/).
- All passwords and keys in this lesson are fake lab values. Never use real ones while practising.

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | Cluster `lab`: one control plane and one worker, pinned node image |
| `app/app.py` | API that reads settings from env vars and files, re-reads `features.properties` every 2 s, never prints the password |
| `app/Dockerfile` | Image 1.5.0: no settings inside |
| `app/Dockerfile.baked` | Priya's image 1.4.0 with production settings baked in (the hook - don't do this) |
| `k8s/api-staging.yaml` | The hook: image 1.4.0 deployed to the `staging` namespace |
| `k8s/features.properties`, `k8s/app.env`, `k8s/nginx/` | Inputs for `--from-file`, `--from-env-file` and a folder |
| `k8s/api-env.yaml` | ConfigMap `api-env` as YAML (four keys) |
| `k8s/api.yaml` | API Deployment: `configMapKeyRef`, `envFrom`, and a ConfigMap volume |
| `k8s/api-secret-file.yaml` | Same, plus the Secret `db-creds` mounted as the file `/etc/secrets/db-password` |
| `k8s/storefront.yaml` | nginx with the whole ConfigMap as `conf.d` and one key via `subPath` |
| `k8s/pricing.yaml` | Immutable ConfigMap `pricing-2026-10` |
| `k8s/smtp.yaml` | Secret with `data` (base64) and `stringData` (plain text) |
| `k8s/enc-template.yaml`, `k8s/edit-apiserver.sh` | EncryptionConfiguration template (secretbox) and the three API-server manifest edits |
| `k8s/legacy-worker.yaml`, `projected.yaml`, `peek.yaml`, `crash-dump.yaml` | Secret as env var, projected volume, RBAC peek, env dump on failure |
| `kind-enc/kind-enc-cluster.yaml` | Optional: a kind cluster with encryption at rest from the start |

## Follow along

1. Create the cluster and build both images.
   ```bash
   kind create cluster --config kind-cluster.yaml
   docker build -t api:1.4.0 -f app/Dockerfile.baked app
   docker build -t api:1.5.0 app
   kind load docker-image api:1.4.0 api:1.5.0 --name lab
   cd k8s
   ```

2. **The hook**: the baked image in staging.
   ```bash
   kubectl create namespace staging
   kubectl apply -f api-staging.yaml
   kubectl -n staging rollout status deploy/api
   kubectl -n staging logs deploy/api
   ```
   You should see a staging pod pointed at production:
   ```
   INFO api 1.4.0 starting · env=production · log_level=WARNING
   INFO database db.prod.allcsvideos.internal:5432 · user api · password from not set
   INFO public url https://api.allcsvideos.com
   ```

3. Four ways to make a ConfigMap.
   ```bash
   kubectl create namespace allcsvideos
   kubectl config set-context --current --namespace allcsvideos
   kubectl create configmap api-logging --from-literal=LOG_LEVEL=INFO
   kubectl get configmap api-logging -o yaml
   cat features.properties
   kubectl create configmap api-features --from-file=features.properties
   kubectl get configmap api-features -o yaml | head -9
   cat app.env
   kubectl create configmap demo --from-env-file=app.env --dry-run=client -o yaml
   ls nginx/
   kubectl create configmap storefront-nginx --from-file=nginx/
   kubectl describe configmap storefront-nginx
   kubectl apply -f api-env.yaml
   kubectl get configmaps
   ```
   `--from-file` makes one key named after the file; `--from-env-file` makes one key per line (`APP_ENV`, `LOG_LEVEL`); a folder makes one key per file. `get configmaps` lists five: yours plus `kube-root-ca.crt`, created in every namespace.

4. Consume them: env vars and a volume.
   ```bash
   kubectl apply -f api.yaml
   kubectl rollout status deploy/api
   kubectl logs deploy/api
   kubectl exec deploy/api -- printenv APP_ENV DB_HOST LOG_LEVEL
   kubectl exec deploy/api -- ls -la /etc/allcsvideos
   kubectl exec deploy/api -- cat /etc/allcsvideos/features.properties
   ```
   You should see:
   ```
   INFO api 1.5.0 starting · env=staging · log_level=INFO
   INFO database db.staging.allcsvideos.internal:5432 · user api · password from not set
   INFO public url https://staging.allcsvideos.com
   INFO features loaded: player.v2=true, copilot.hints=false, checkout.upi=true
   ...
   lrwxrwxrwx ... ..data -> ..2026_10_21_01_39_55.1736201677
   lrwxrwxrwx ... features.properties -> ..data/features.properties
   ```
   Same image, staging settings. The `..data` symlink is what the kubelet swaps on updates.

5. The storefront: a whole folder plus one file via `subPath`.
   ```bash
   kubectl apply -f storefront.yaml
   kubectl rollout status deploy/storefront
   kubectl exec deploy/storefront -- curl -sI 127.0.0.1 | grep X-
   ```
   `X-Frame-Options: DENY` and `X-Env: staging`.

6. How often does the kubelet look?
   ```bash
   kubectl get --raw /api/v1/nodes/lab-worker/proxy/configz | jq '.kubeletconfig | {syncFrequency, configMapAndSecretChangeDetectionStrategy}'
   ```
   `"syncFrequency": "1m0s"`, `"configMapAndSecretChangeDetectionStrategy": "Watch"`.

7. Change config while it runs. Terminal 2 (in `k8s/`): `kubectl logs -f deploy/api`. Terminal 1:
   ```bash
   sed -i.bak 's/copilot.hints=false/copilot.hints=true/' features.properties && rm features.properties.bak
   date +%T; kubectl create configmap api-features --from-file=features.properties --dry-run=client -o yaml | kubectl apply -f -
   kubectl patch configmap api-logging -p '{"data":{"LOG_LEVEL":"DEBUG"}}'
   kubectl exec deploy/api -- grep hints /etc/allcsvideos/features.properties
   ```
   Apply warns that the ConfigMap is missing the last-applied annotation (it was created imperatively), then `configured`. Right away the file still says `copilot.hints=false`. Wait, and repeat the `grep` until it says `true`; the app logs `features loaded: ... copilot.hints=true` on its own. In the video that took 76 s (eight trials: 53 to 82 s). Plan for minutes, not seconds. But:
   ```bash
   kubectl exec deploy/api -- printenv LOG_LEVEL
   ```
   Still `INFO`: env vars never update in a running container.

8. The `subPath` trap.
   ```bash
   sed -i.bak 's/"staging"/"staging-2"/' nginx/headers.inc && rm nginx/headers.inc.bak
   date +%T; kubectl create configmap storefront-nginx --from-file=nginx/ --dry-run=client -o yaml | kubectl apply -f -
   ```
   Wait about two minutes, then:
   ```bash
   date +%T; kubectl exec deploy/storefront -- grep X-Env /etc/nginx/conf.d/headers.inc /etc/nginx/headers.inc
   kubectl exec deploy/storefront -- curl -sI 127.0.0.1 | grep X-Env
   ```
   You should see:
   ```
   /etc/nginx/conf.d/headers.inc:add_header X-Env "staging-2" always;
   /etc/nginx/headers.inc:add_header X-Env "staging" always;
   X-Env: staging
   ```

9. New pods pick up everything.
   ```bash
   kubectl rollout restart deployment api storefront
   kubectl rollout status deploy/api && kubectl rollout status deploy/storefront
   kubectl exec deploy/api -- printenv LOG_LEVEL
   kubectl exec deploy/storefront -- curl -sI 127.0.0.1 | grep X-Env
   kubectl get deploy api -o jsonpath='{.spec.template.metadata.annotations}'; echo
   ```
   `DEBUG`, `X-Env: staging-2`, and `{"kubectl.kubernetes.io/restartedAt":"..."}`.

10. The checksum pattern: a config hash in the pod template.
    ```bash
    sed -i.bak 's/db.staging/pg-staging/' api-env.yaml && rm api-env.yaml.bak
    kubectl apply -f api-env.yaml
    SUM=$(sha256sum api-env.yaml | cut -c1-12); echo $SUM
    kubectl patch deployment api -p '{"spec":{"template":{"metadata":{"annotations":{"checksum/config":"'$SUM'"}}}}}'
    kubectl rollout status deploy/api
    kubectl patch deployment api -p '{"spec":{"template":{"metadata":{"annotations":{"checksum/config":"'$SUM'"}}}}}'
    kubectl logs deploy/api | grep database
    kubectl get rs -l app=api
    ```
    The first patch rolls out; the same hash again says `patched (no change)`. The new pod logs `pg-staging.allcsvideos.internal`, and there's a third ReplicaSet. (macOS: `shasum -a 256` instead of `sha256sum`. In the video the hash was `cd726f78924b`.)

11. Immutable ConfigMaps and the size limit.
    ```bash
    kubectl apply -f pricing.yaml
    kubectl patch configmap pricing-2026-10 -p '{"data":{"DSA_PRICE_INR":"399"}}'
    kubectl patch configmap pricing-2026-10 -p '{"immutable":false}'
    yes 'dsa-101,Arrays and Strings,499' | head -c 1100000 > catalog.csv
    ls -l catalog.csv
    kubectl create configmap catalog --from-file=catalog.csv
    rm catalog.csv
    ```
    Both patches: `Forbidden: field is immutable when 'immutable' is set`. The big file: `Too long: may not be more than 1048576 bytes` (1 MiB, the same limit as Secrets).

12. Create Secrets.
    ```bash
    kubectl create secret generic db-creds --from-literal=username=api --from-literal=password=demo-password-123
    printf 'FAKE-copilot-key-0001' > copilot.key
    kubectl create secret generic copilot-key --from-file=api-key=copilot.key
    rm copilot.key
    kubectl get secrets
    kubectl describe secret db-creds
    ```
    Both type `Opaque`; describe shows only sizes: `password: 17 bytes`, `username: 3 bytes`.

13. Secret YAML: `data` vs `stringData`, and the annotation that leaks.
    ```bash
    printf 'mailer@example.com' | base64
    kubectl apply -f smtp.yaml
    kubectl get secret smtp -o yaml | grep -A2 '^data'
    kubectl get secret smtp -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' | jq .stringData
    kubectl delete secret smtp
    kubectl apply --server-side -f smtp.yaml
    kubectl get secret smtp -o jsonpath='{.metadata.annotations}'; echo
    ```
    `stringData` is gone from the stored object - but the client-side apply annotation holds `"password": "FAKE-smtp-pass-42"` in plain text. Server-side apply writes no such annotation (empty output).

14. Built-in Secret types and pull secrets.
    ```bash
    kubectl create secret docker-registry regcred --docker-server=registry.example.com --docker-username=ci-bot --docker-password=FAKE-registry-token-0001
    openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj /CN=staging.allcsvideos.com -keyout tls.key -out tls.crt 2>/dev/null
    kubectl create secret tls storefront-tls --cert=tls.crt --key=tls.key
    rm tls.key tls.crt
    kubectl get secrets
    kubectl explain pod.spec.imagePullSecrets | head -12
    kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"regcred"}]}'
    kubectl run pulltest --image=busybox:1.37.0 --restart=Never -- true; kubectl get pod pulltest -o jsonpath='{.spec.imagePullSecrets}'; echo
    ```
    Types `kubernetes.io/dockerconfigjson` and `kubernetes.io/tls`; `pulltest` gets `[{"name":"regcred"}]` without naming it.

15. **Base64 is not encryption.**
    ```bash
    kubectl get secret db-creds -o jsonpath='{.data.password}'; echo
    kubectl get secret db-creds -o jsonpath='{.data.password}' | base64 -d; echo
    kubectl get secret regcred -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq
    echo Y2ktYm90OkZBS0UtcmVnaXN0cnktdG9rZW4tMDAwMQ== | base64 -d; echo
    ```
    `ZGVtby1wYXNzd29yZC0xMjM=` decodes to `demo-password-123`; the registry password is in clear, and `auth` is just `ci-bot:FAKE-registry-token-0001`.

16. Look in etcd (read-only, in your own lab cluster).
    ```bash
    E='--cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key'
    kubectl -n kube-system exec etcd-lab-control-plane -- etcdctl $E get /registry/secrets/allcsvideos/db-creds | hexdump -C
    ```
    The key, `k8s`, a protobuf Secret named `db-creds`... and further down `password` followed by `demo-password-123` in plain bytes. (No `hexdump`? Use `xxd` or `od -c`.)

17. **Encryption at rest.** Make a config with a random 32-byte key (never printed), put it on the control-plane node as root with mode 600:
    ```bash
    sed "s|KEY|$(head -c 32 /dev/urandom | base64)|" enc-template.yaml > enc.yaml
    docker exec lab-control-plane mkdir -p /etc/kubernetes/enc
    docker cp enc.yaml lab-control-plane:/etc/kubernetes/enc/enc.yaml
    docker exec lab-control-plane sh -c 'chown root:root /etc/kubernetes/enc/enc.yaml; chmod 600 /etc/kubernetes/enc/enc.yaml'
    ```
    The node is a container, so `docker cp`/`docker exec` reach it (on a real cluster you'd SSH in). Now the three manifest edits (flag, volumeMount, hostPath volume). The script uses GNU sed, so run it inside the node, on a copy in `/tmp`, and look at the diff:
    ```bash
    docker cp edit-apiserver.sh lab-control-plane:/tmp/edit-apiserver.sh
    docker exec lab-control-plane sh -c 'cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml && cp /tmp/kube-apiserver.yaml /tmp/kube-apiserver.yaml.orig && sh /tmp/edit-apiserver.sh /tmp/kube-apiserver.yaml && diff -u /tmp/kube-apiserver.yaml.orig /tmp/kube-apiserver.yaml'
    ```
    You should see three `+` blocks: `--encryption-provider-config=/etc/kubernetes/enc/enc.yaml`, a `volumeMounts` entry and a `hostPath` volume. Put it in place; the kubelet restarts the API server by itself (about 40 s of outage with one control plane):
    ```bash
    docker exec lab-control-plane cp /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml
    date +%T; while kubectl get --raw /readyz >/dev/null 2>&1; do sleep 1; done; echo "down $(date +%T)"; until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 1; done; echo "up   $(date +%T)"
    kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep encryption
    ```

18. New writes are encrypted; old ones aren't until rewritten.
    ```bash
    kubectl create secret generic payments-key --from-literal=key=FAKE-payments-key-0001
    kubectl -n kube-system exec etcd-lab-control-plane -- etcdctl $E get /registry/secrets/allcsvideos/payments-key | hexdump -C | head -8
    kubectl -n kube-system exec etcd-lab-control-plane -- etcdctl $E get /registry/secrets/allcsvideos/db-creds | grep -ac demo-password
    kubectl get secrets --all-namespaces -o json | kubectl replace -f -
    kubectl -n kube-system exec etcd-lab-control-plane -- etcdctl $E get /registry/secrets/allcsvideos/db-creds | grep -ac demo-password
    kubectl -n kube-system exec etcd-lab-control-plane -- etcdctl $E get /registry/secrets/allcsvideos/db-creds | hexdump -C | sed -n 3,4p
    kubectl get secret db-creds -o jsonpath='{.data.password}' | base64 -d; echo
    ```
    `payments-key` starts with `k8s:enc:secretbox:v1:key1:` and random bytes. `db-creds` counts `1` (still plain) until the `replace` rewrites every Secret, then `0` and the prefix is there. Through the API it still decodes to `demo-password-123`: encryption at rest protects the disk and the backups, not the API.

    **Optional - encryption from day one.** Copy `enc.yaml` into `kind-enc/`, then create, check and delete a throwaway cluster:
    ```bash
    cd ..
    cp k8s/enc.yaml kind-enc/enc.yaml
    sed "s|ENC_DIR|$PWD/kind-enc|" kind-enc/kind-enc-cluster.yaml > kind-enc/cluster.yaml
    kind create cluster --name lab-enc --config kind-enc/cluster.yaml
    kubectl --context kind-lab-enc create secret generic t --from-literal=k=FAKE
    kubectl --context kind-lab-enc -n kube-system exec etcd-lab-enc-control-plane -- etcdctl $E get /registry/secrets/default/t | hexdump -C | head -4
    kind delete cluster --name lab-enc
    kubectl config use-context kind-lab
    rm kind-enc/enc.yaml kind-enc/cluster.yaml
    cd k8s
    ```
    The dump shows `k8s:enc:secretbox:v1:key1` from the first Secret. (Docker Desktop must be allowed to share this folder; your home folder is shared by default.)

19. Secret as a file vs as an env var.
    ```bash
    kubectl apply -f api-secret-file.yaml
    kubectl rollout status deploy/api
    kubectl logs deploy/api | grep password
    kubectl exec deploy/api -- ls -l /etc/secrets
    kubectl exec deploy/api -- df -h /etc/secrets
    kubectl apply -f legacy-worker.yaml && kubectl wait --for=condition=Ready pod/legacy-worker
    kubectl describe pod legacy-worker | grep DB_PASSWORD
    kubectl exec legacy-worker -- env | grep DB_
    kubectl exec legacy-worker -- cat /proc/1/environ | tr '\0' '\n' | grep DB_
    ```
    The API logs `password from file /etc/secrets/db-password (17 chars)`; the folder is `tmpfs` (memory only). For the env-var pod, `describe` is polite (`<set to the key 'password' in secret 'db-creds'>`), but `env` and `/proc/1/environ` print `DB_PASSWORD=demo-password-123`.

20. A projected volume: one folder, three sources.
    ```bash
    kubectl apply -f projected.yaml && kubectl wait --for=condition=Ready pod/projected-demo
    kubectl exec projected-demo -- ls /etc/app
    kubectl exec projected-demo -- cat /etc/app/labels; echo
    ```
    `db-password`, `features.properties`, `labels` (`app="projected-demo"`).

21. RBAC surprise 1: creating pods reveals Secrets.
    ```bash
    kubectl create serviceaccount ci-deployer
    kubectl create role deployer --verb=get,list,create,delete --resource=pods,pods/log,deployments.apps
    kubectl create rolebinding ci-deployer --role=deployer --serviceaccount=allcsvideos:ci-deployer
    SA=system:serviceaccount:allcsvideos:ci-deployer
    kubectl auth can-i get secrets --as=$SA
    kubectl auth can-i create pods --as=$SA
    kubectl get secret db-creds --as=$SA
    kubectl apply -f peek.yaml --as=$SA
    sleep 5; kubectl logs peek --as=$SA
    ```
    `no`, `yes`, `Forbidden` - and then the pod's log prints `demo-password-123`.

22. RBAC surprise 2: `list` is as good as `get`.
    ```bash
    kubectl create serviceaccount dashboard
    kubectl create role secret-lister --verb=list --resource=secrets
    kubectl create rolebinding dashboard --role=secret-lister --serviceaccount=allcsvideos:dashboard
    D=system:serviceaccount:allcsvideos:dashboard
    kubectl auth can-i get secret/db-creds --as=$D
    kubectl get secrets --as=$D -o jsonpath='{.items[?(@.metadata.name=="db-creds")].data.password}' | base64 -d; echo
    ```
    `no`, then `demo-password-123`.

23. Pitfalls, live: env dumps and shell history.
    ```bash
    kubectl apply -f crash-dump.yaml
    sleep 5; kubectl get pod crash-dump
    kubectl logs crash-dump
    history | grep -- --from-literal=password
    ```
    The log contains `DB_PASSWORD=demo-password-123`; your shell history still holds the `--from-literal` command from step 12.

## Common mistakes
- **Committing Secret YAML to git.** base64 is not protection and git history keeps it forever. Commit sealed or encrypted files (Sealed Secrets, SOPS), or nothing.
- **`--from-literal` for passwords.** It lands in your shell history. Prefer `--from-file`, from a file you delete afterwards.
- **Secrets in env vars that reach the logs.** Crash dumps, debug pages and child processes all carry the environment. Prefer files.
- **Huge ConfigMaps.** The limit is 1 MiB (1,048,576 bytes) for ConfigMaps and Secrets. Big data belongs in a volume, a database or object storage.
- **Forgetting the rollout.** Env vars and `subPath` files keep the old value until pods restart. Use a checksum annotation or a new (immutable) name.
- **Broad RBAC on Secrets.** `list` and `watch` reveal values just like `get`, and anyone who can create pods in a namespace can read its Secrets. Separate teams' secrets by namespace.
- **Thinking encryption at rest stops the API.** It protects etcd's disk and backups; RBAC decides who reads through the API.

## Clean up
From the lesson folder (one level above `k8s/`):
```bash
rm -f k8s/enc.yaml
git checkout -- k8s/features.properties k8s/nginx/headers.inc k8s/api-env.yaml 2>/dev/null || true
kind delete cluster --name lab
docker rmi api:1.4.0 api:1.5.0
```
(The `git checkout` line restores the three files you edited, if you cloned the course repo. To clean your shell history, delete the `--from-literal=password` line from `~/.bash_history`.)

## Next
[M14-L01 · Ingress and the Gateway API](../m14-l01-ingress-and-the-gateway-api/)
