# M14-L01 · Ingress and the Gateway API
> Video: Module 14, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- Why one LoadBalancer per service doesn't scale (cost, DNS, certificates, no host/path routing), and what an Ingress controller does instead.
- Ingress with Traefik: host and path rules, `pathType` edge cases, default backends, and why annotations don't travel between controllers.
- cert-manager: a private lab CA, Certificates that become Secrets, automatic renewal, and a real ACME HTTP-01 flow against Pebble.
- The Gateway API with NGINX Gateway Fabric: GatewayClass, Gateway, HTTPRoute, typed rewrites, header matches, weighted canaries, ReferenceGrant.
- Migrating with ingress2gateway, and why the community ingress-nginx project's retirement (archived 24 March 2026) matters.

## Before you start
- Docker Desktop (or Docker Engine on Linux) with about 4 GB of memory, `curl`, `jq`, `openssl`.
- kind **v0.33.0**, kubectl **v1.37.1**.
- Helm **v4.3.1** (https://helm.sh/docs/intro/install/), cmctl **v2.6.1** (https://github.com/cert-manager/cmctl/releases), ingress2gateway **v1.2.0** (https://github.com/kubernetes-sigs/ingress2gateway/releases).
- Node image `kindest/node:v1.36.4`, pinned in `kind-cluster.yaml`. Not 1.37: cert-manager 1.21 supports Kubernetes up to 1.36. Add-ons trail Kubernetes; check their support tables before you upgrade.
- Free local ports 8480, 8443, 9480, 9443.
- Services and DNS from [M13-L05](../m13-l05-services-and-dns/), Secrets from [M13-L06](../m13-l06-configmaps-and-secrets/).

Pinned versions used below: Traefik chart 42.1.0 (Traefik v3.7.15), cert-manager v1.21.2, Pebble 2.10.1, Gateway API v1.6.3 (standard channel), NGINX Gateway Fabric 2.8.0.

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | Cluster `lab` (1 control plane + 1 worker, v1.36.4); maps 8480/8443 -> Traefik and 9480/9443 -> the Gateway |
| `app/app.py`, `app/Dockerfile` | One small image for all services; every answer shows `service`, `version`, the `path` it received and the pod |
| `manifests/apps.yaml` | storefront (2), api-v1 (2), copilot (1), each with a ClusterIP Service on port 80 |
| `manifests/traefik-values.yaml`, `traefik-values-strict.yaml` | Traefik Helm values: NodePort 30480/30443, non-default IngressClass; the second adds `strictPrefixMatching` |
| `manifests/ingress-hosts.yaml`, `ingress-paths.yaml` | Ingress by host, then by path (Prefix and Exact) |
| `manifests/catch-all.yaml` | Ingress with only a `defaultBackend` |
| `manifests/ingress-nginx-annot.yaml`, `ingress-traefik-annot.yaml` | Staged mistake (ingress-nginx annotation on Traefik), then Traefik's Middleware way |
| `manifests/noclass.yaml` | Staged mistake: an Ingress without `ingressClassName` |
| `manifests/issuers.yaml`, `certificate.yaml`, `ingress-tls.yaml`, `copilot-ingress.yaml` | Lab CA issuers, the site Certificate, TLS on the Ingress, and the one-annotation shortcut |
| `manifests/pebble.yaml`, `acme-issuer.yaml`, `corefile-hosts.txt`, `www-ingress.yaml`, `shop-ingress.yaml` | ACME with Pebble: server, issuer, in-cluster DNS names, a working and a failing HTTP-01 certificate |
| `manifests/ngf-values.yaml`, `gateway.yaml`, `routes.yaml` | NGINX Gateway Fabric values, the shared Gateway, the HTTPRoutes |
| `manifests/api-v2.yaml`, `api-canary.yaml` | API 2.0.0 and the 90/10 + header canary route |
| `manifests/copilot-team.yaml`, `site-crossns.yaml`, `referencegrant.yaml` | Cross-namespace routing and the ReferenceGrant that allows it |

## Follow along

All commands run from the `manifests` folder after step 1. No DNS exists for `*.allcsvideos.test`, so `curl --resolve name:port:127.0.0.1` pins the name to your laptop and still sends the real Host header.

### Part 1: Ingress with Traefik

1. Cluster, image, apps.
   ```bash
   kind create cluster --config kind-cluster.yaml
   docker build -q -t svc:1.0 app
   kind load docker-image svc:1.0 --name lab
   cd manifests
   kubectl create namespace allcsvideos
   kubectl config set-context --current --namespace allcsvideos
   kubectl apply -f apps.yaml
   kubectl wait --for=condition=Available deploy --all --timeout=90s
   kubectl get pods,svc
   ```

2. The hook: three LoadBalancers, three pending addresses.
   ```bash
   for d in storefront api-v1 copilot; do kubectl expose deploy $d --name $d-lb --type LoadBalancer --port 80 --target-port http; done
   sleep 30; kubectl get svc -o wide
   kubectl delete svc storefront-lb api-v1-lb copilot-lb
   ```
   `EXTERNAL-IP <pending>` for all three. On AWS each would be a separate Network Load Balancer (about $16 a month each, before traffic).

3. Install Traefik with Helm.
   ```bash
   cat traefik-values.yaml
   helm install traefik oci://ghcr.io/traefik/helm/traefik --version 42.1.0 --namespace traefik --create-namespace -f traefik-values.yaml
   kubectl -n traefik rollout status deploy/traefik --timeout=120s
   kubectl -n traefik get pods,svc
   kubectl get ingressclass
   ```
   Service `traefik` NodePort `80:30480/TCP,443:30443/TCP`, and IngressClass `traefik` with controller `traefik.io/ingress-controller`.

4. Route by host name.
   ```bash
   curl -s 127.0.0.1:8480/
   kubectl apply -f ingress-hosts.yaml
   kubectl get ingress
   curl -s --resolve allcsvideos.test:8480:127.0.0.1 http://allcsvideos.test:8480/
   curl -s --resolve api.allcsvideos.test:8480:127.0.0.1 http://api.allcsvideos.test:8480/courses
   curl -s -o /dev/null -w '%{http_code}\n' 127.0.0.1:8480/
   ```
   You should see:
   ```
   404 page not found
   ...
   {"service": "storefront", "version": "1.0.0", "path": "/", "pod": "storefront-566459657c-n4grx"}
   {"service": "api", "version": "1.0.0", "path": "/courses", "pod": "api-v1-56cfc85979-84wf4"}
   404
   ```
   To try it in a browser, add `127.0.0.1 allcsvideos.test api.allcsvideos.test` to your hosts file (`/etc/hosts`, or `C:\Windows\System32\drivers\etc\hosts`) and open http://allcsvideos.test:8480/. Remove the line when you're done.

5. Route by path, and test the edges.
   ```bash
   kubectl apply -f ingress-paths.yaml
   for p in /api /api/courses /apiary /copilot /copilot/ /copilot/ask; do printf '%-13s' $p; curl -s --resolve allcsvideos.test:8480:127.0.0.1 http://allcsvideos.test:8480$p | jq -c '{service,path}'; done
   ```
   You should see:
   ```
   /api         {"service":"api","path":"/api"}
   /api/courses {"service":"api","path":"/api/courses"}
   /apiary      {"service":"api","path":"/apiary"}
   /copilot     {"service":"copilot","path":"/copilot"}
   /copilot/    {"service":"storefront","path":"/copilot/"}
   /copilot/ask {"service":"storefront","path":"/copilot/ask"}
   ```
   Exact means exact. But `/apiary` went to the API - the Ingress spec says Prefix matches path elements, so it shouldn't. Traefik's default is a character-by-character prefix.

6. Make Traefik follow the spec.
   ```bash
   tail -3 traefik-values-strict.yaml
   helm upgrade traefik oci://ghcr.io/traefik/helm/traefik --version 42.1.0 -n traefik -f traefik-values-strict.yaml >/dev/null
   kubectl -n traefik rollout status deploy/traefik
   for p in /api /api/courses /apiary; do printf '%-13s' $p; curl -s --resolve allcsvideos.test:8480:127.0.0.1 http://allcsvideos.test:8480$p | jq -c '{service,path}'; done
   ```
   Now `/apiary {"service":"storefront","path":"/apiary"}`. Same YAML, different behavior per controller.

7. Per-request balancing and a catch-all.
   ```bash
   curl -s --resolve allcsvideos.test:8480:127.0.0.1 http://allcsvideos.test:8480/{a,b,c,d} | jq -r .pod
   curl -s -w '%{http_code}\n' --resolve www.allcsvideos.test:8480:127.0.0.1 http://www.allcsvideos.test:8480/
   kubectl apply -f catch-all.yaml
   curl -s --resolve www.allcsvideos.test:8480:127.0.0.1 http://www.allcsvideos.test:8480/ | jq -c '{service,path}'
   kubectl get ingress
   ```
   One connection, four requests: the two storefront pods alternate (a proxy balances requests). `www` is `404` until the catch-all, then the storefront; `catch-all` shows host `*`.

8. Strip `/api`: the wrong annotation, then Traefik's way.
   ```bash
   kubectl apply -f ingress-nginx-annot.yaml
   curl -s --resolve allcsvideos.test:8480:127.0.0.1 http://allcsvideos.test:8480/api/courses | jq -c '{service,path}'
   kubectl apply -f ingress-traefik-annot.yaml
   curl -s --resolve allcsvideos.test:8480:127.0.0.1 http://allcsvideos.test:8480/api/courses | jq -c '{service,path}'
   curl -s --resolve allcsvideos.test:8480:127.0.0.1 http://allcsvideos.test:8480/courses | jq -c '{service,path}'
   ```
   The ingress-nginx annotation applies with no error and does nothing (`"path":"/api/courses"`). With the Traefik Middleware: `{"service":"api","path":"/courses"}`.

9. Staged mistake: no `ingressClassName`.
   ```bash
   kubectl apply -f noclass.yaml
   kubectl get ingress copilot
   curl -s --resolve copilot.allcsvideos.test:8480:127.0.0.1 http://copilot.allcsvideos.test:8480/ | jq -c '{service,path}'
   kubectl delete ingress copilot
   kubectl annotate ingressclass traefik --overwrite ingressclass.kubernetes.io/is-default-class=true
   kubectl apply -f noclass.yaml
   kubectl get ingress copilot
   ```
   First `CLASS <none>`, yet Traefik serves it (it takes class-less Ingresses by default; ingress-nginx doesn't). With a default IngressClass, the same file gets `CLASS traefik`.

### TLS with cert-manager

10. Install cert-manager.
    ```bash
    helm install cert-manager oci://quay.io/jetstack/charts/cert-manager --version v1.21.2 --namespace cert-manager --create-namespace --set crds.enabled=true
    kubectl -n cert-manager get pods
    cmctl check api --wait=2m
    kubectl api-resources --api-group=cert-manager.io
    ```
    Three pods (controller, cainjector, webhook), `The cert-manager API is ready`, and four kinds: Certificate, CertificateRequest, Issuer, ClusterIssuer.

11. A lab CA in three objects, then the site certificate.
    ```bash
    kubectl apply -f issuers.yaml
    kubectl get clusterissuers
    kubectl -n cert-manager get certificate lab-root-ca
    kubectl apply -f certificate.yaml
    kubectl wait --for=condition=Ready certificate/allcsvideos-tls --timeout=60s
    kubectl get certificate,certificaterequest
    kubectl get secret allcsvideos-tls
    kubectl describe certificate allcsvideos-tls | sed -n '/^Status:/,$p'
    ```
    Both issuers `True`; a CertificateRequest approved and ready, issued by `lab-ca`; a Secret of type `kubernetes.io/tls` with 3 keys; `Not After` 90 days out and `Renewal Time` 30 days before that.

12. TLS on the Ingress.
    ```bash
    kubectl apply -f ingress-tls.yaml
    kubectl get secret allcsvideos-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > lab-root.crt
    curl -sv --cacert lab-root.crt --resolve allcsvideos.test:8443:127.0.0.1 https://allcsvideos.test:8443/ 2>&1 | grep -E 'SSL connection|subject|start date|expire date|issuer|verify result|< HTTP|service'
    curl -s --resolve api.allcsvideos.test:8443:127.0.0.1 https://api.allcsvideos.test:8443/; echo "exit code $?"
    curl -s --cacert lab-root.crt --resolve api.allcsvideos.test:8443:127.0.0.1 https://api.allcsvideos.test:8443/courses
    ```
    You should see `TLSv1.3`, `issuer: CN=allcsvideos lab root CA`, `verify result: 0`, `HTTP/2 200`; without `--cacert`: `exit code 60` (nobody trusts a private root). The exact curl wording depends on your curl/TLS library.

13. The short way, and renewal.
    ```bash
    kubectl apply -f copilot-ingress.yaml
    kubectl get certificate
    kubectl get certificate copilot-tls -o jsonpath='{.metadata.ownerReferences[0].kind}{"/"}{.metadata.ownerReferences[0].name}{"\n"}'
    curl -s --cacert lab-root.crt --resolve copilot.allcsvideos.test:8443:127.0.0.1 https://copilot.allcsvideos.test:8443/ask
    cmctl status certificate allcsvideos-tls | grep -E '^(Not|Renewal)'
    openssl s_client -connect 127.0.0.1:8443 -servername api.allcsvideos.test </dev/null 2>/dev/null | openssl x509 -noout -serial -enddate
    cmctl renew allcsvideos-tls
    kubectl get certificaterequest
    kubectl describe certificate allcsvideos-tls | tail -4
    openssl s_client -connect 127.0.0.1:8443 -servername api.allcsvideos.test </dev/null 2>/dev/null | openssl x509 -noout -serial -enddate
    ```
    `copilot-tls` is created for you, owned by `Ingress/copilot`. After `cmctl renew`: a second CertificateRequest (`allcsvideos-tls-2`), a new private key, and the live server's `serial=` changes - Traefik loaded the new Secret by itself.

14. ACME with Pebble (Let's Encrypt's test server) in the cluster.
    ```bash
    kubectl apply -f pebble.yaml
    kubectl -n pebble rollout status deploy/pebble --timeout=120s
    sed "s/LAB_ROOT_CA_BASE64/$(base64 < lab-root.crt | tr -d '\n')/" acme-issuer.yaml | kubectl apply -f -
    kubectl get clusterissuer pebble
    kubectl describe clusterissuer pebble | grep -E 'Uri|Reason|Message'
    ```
    `pebble True`, `The ACME account was registered with the ACME server`. For Let's Encrypt only the `server:` line changes.

15. HTTP-01 needs the name to resolve to your entry point. Add a hosts block to CoreDNS that points three names at Traefik's cluster IP:
    ```bash
    TRAEFIK_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.spec.clusterIP}')
    sed "s/TRAEFIK_IP/$TRAEFIK_IP/" corefile-hosts.txt > hosts-block.txt
    cat hosts-block.txt
    kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' > Corefile
    awk '/prometheus/{system("cat hosts-block.txt")} 1' Corefile > Corefile.new
    kubectl -n kube-system patch cm coredns --type merge -p "$(jq -n --rawfile c Corefile.new '{data:{Corefile:$c}}')"
    kubectl -n kube-system rollout restart deploy/coredns
    kubectl -n kube-system rollout status deploy/coredns
    ```

16. Get a real ACME certificate. Terminal 2: `kubectl get challenge -w`. Terminal 1:
    ```bash
    kubectl apply -f www-ingress.yaml
    kubectl get pods,ingress -l acme.cert-manager.io/http01-solver=true
    kubectl wait --for=condition=Ready certificate/www-tls --timeout=120s
    kubectl get certificate www-tls; kubectl get order
    kubectl -n pebble logs deploy/pebble | grep -iE 'http-01|validat' | cut -c1-108
    ```
    A solver pod and a temporary Ingress appear; the challenge goes `pending` -> `valid` in about 20 s; the order is `valid`. Pebble's log shows `Attempting to validate w/ HTTP: http://www.allcsvideos.test:80/.well-known/acme-challenge/...`. Check it, trusting Pebble's throwaway root (lab only):
    ```bash
    kubectl -n pebble port-forward svc/pebble 15000 >/dev/null &
    sleep 2; curl -sk https://127.0.0.1:15000/roots/0 > pebble-root.pem
    curl -sv --cacert pebble-root.pem --resolve www.allcsvideos.test:8443:127.0.0.1 https://www.allcsvideos.test:8443/ 2>&1 | grep -E 'issuer|expire date|verify result|service'
    kill %1
    ```
    `issuer: CN=Pebble Intermediate CA ...`, `verify result: 0`.

17. Staged mistake: a certificate that never becomes Ready (no DNS for `shop`).
    ```bash
    kubectl apply -f shop-ingress.yaml
    sleep 40; kubectl get certificate shop-tls
    kubectl get challenge
    kubectl describe challenge | grep -A3 '^  Reason'
    ```
    `READY False`, challenge `pending`, and `failed to perform self check GET request 'http://shop.allcsvideos.test/.well-known/acme-challenge/...'` ... `no such host`.

### Part 2: the Gateway API with NGINX Gateway Fabric

18. CRDs, the implementation, and cert-manager's Gateway support.
    ```bash
    kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml
    cat ngf-values.yaml
    helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric --version 2.8.0 --namespace nginx-gateway --create-namespace -f ngf-values.yaml | head -6
    kubectl -n nginx-gateway rollout status deploy/ngf-nginx-gateway-fabric --timeout=3m
    kubectl -n nginx-gateway get pods
    kubectl get gatewayclass
    helm upgrade cert-manager oci://quay.io/jetstack/charts/cert-manager --version v1.21.2 -n cert-manager --reuse-values --set config.gatewayAPI.enabled=true >/dev/null
    kubectl -n cert-manager rollout status deploy/cert-manager
    kubectl -n cert-manager logs deploy/cert-manager | grep -i 'gateway' | cut -c1-140 | head -5
    ```
    Ten CRDs plus the `safe-upgrades` admission policy; GatewayClass `nginx` `ACCEPTED True`; cert-manager logs `enabling the sig-network Gateway API certificate-shim and HTTP-01 solver`.

19. The operator's Gateway.
    ```bash
    kubectl apply -f gateway.yaml
    kubectl label namespace allcsvideos shared-gateway-access=true
    kubectl -n gateway-infra wait --for=condition=Programmed gateway/allcsvideos --timeout=120s
    kubectl -n gateway-infra get gateway
    kubectl -n gateway-infra get pods,svc
    kubectl -n gateway-infra get certificate
    ```
    `PROGRAMMED True`, an NGINX pod and a NodePort Service `80:31480/TCP,443:31443/TCP` just for this Gateway, and two Certificates (`api-gw-tls`, `site-gw-tls`) Ready.

20. The developer's routes.
    ```bash
    kubectl apply -f routes.yaml
    kubectl get httproute
    kubectl get httproute site -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {end}{"\n"}'
    for p in /api /api/courses /apiary /copilot/ask /; do printf '%-13s' $p; curl -s --resolve allcsvideos.test:9480:127.0.0.1 http://allcsvideos.test:9480$p | jq -c '{service,path}'; done
    kubectl -n gateway-infra get gateway allcsvideos -o jsonpath='{range .status.listeners[*]}{.name}{"  attachedRoutes="}{.attachedRoutes}{"\n"}{end}'
    curl -sv --cacert lab-root.crt --resolve api.allcsvideos.test:9443:127.0.0.1 https://api.allcsvideos.test:9443/courses 2>&1 | grep -E 'subjectAlt|expire date|issuer|verify result|< HTTP|service'
    kubectl -n gateway-infra get secret api-gw-tls site-gw-tls
    ```
    You should see:
    ```
    Accepted=True ResolvedRefs=True
    /api         {"service":"api","path":"/"}
    /api/courses {"service":"api","path":"/courses"}
    /apiary      {"service":"storefront","path":"/apiary"}
    /copilot/ask {"service":"copilot","path":"/copilot/ask"}
    /            {"service":"storefront","path":"/"}
    http  attachedRoutes=2
    https-site  attachedRoutes=1
    https-api  attachedRoutes=1
    ```
    and HTTPS issued by the lab root, `verify result: 0`.

21. A canary: header match plus a 90/10 split.
    ```bash
    kubectl apply -f api-v2.yaml
    kubectl rollout status deploy/api-v2
    kubectl apply -f api-canary.yaml
    time (for i in $(seq 1000); do curl -s --resolve api.allcsvideos.test:9480:127.0.0.1 http://api.allcsvideos.test:9480/ | jq -r .version; done | sort | uniq -c)
    for i in 1 2 3 4 5; do curl -s -H 'x-canary: always' --resolve api.allcsvideos.test:9480:127.0.0.1 http://api.allcsvideos.test:9480/ | jq -r .version; done | sort | uniq -c
    ```
    About 90/10 (890 vs 110 in the video, never exact), and `5 2.0.0` with the header.

22. Cross-namespace routing needs a ReferenceGrant.
    ```bash
    kubectl apply -f copilot-team.yaml
    kubectl -n copilot rollout status deploy/copilot
    kubectl apply -f site-crossns.yaml
    kubectl get httproute site -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
    curl -s -w '%{http_code}\n' -o /dev/null --resolve allcsvideos.test:9480:127.0.0.1 http://allcsvideos.test:9480/copilot/ask
    kubectl apply -f referencegrant.yaml
    kubectl get httproute site -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
    curl -s --resolve allcsvideos.test:9480:127.0.0.1 http://allcsvideos.test:9480/copilot/ask | jq -c .
    ```
    First `ResolvedRefs=False RefNotPermitted` and `500`; after the grant `ResolvedRefs=True` and Copilot `2.0.0` answers.

23. Migration help, and an exposure audit.
    ```bash
    ingress2gateway print --providers=traefik -n allcsvideos --no-color > converted.yaml 2> warnings.txt
    grep -E '^kind|^  name' converted.yaml
    grep -o 'annotation.*converted' warnings.txt | sort -u
    kubectl get ingress -A
    kubectl get httproute -A
    kubectl get svc -A | grep -E 'NodePort|LoadBalancer'
    ```
    One Gateway and five HTTPRoutes, plus a warning that the Traefik middleware annotation `will not be converted` (the Gateway API equivalent is the URLRewrite filter you already wrote). The audit shows two entry points: `traefik` and `allcsvideos-nginx`.

## Common mistakes
- **Controller-specific annotations.** An ingress-nginx annotation on Traefik does nothing, without an error. Annotations don't travel, and a typo fails silently.
- **Forgetting `ingressClassName`.** Behavior depends on the controller. Always set it, and mark exactly one IngressClass as the default.
- **`pathType` surprises.** Exact `/copilot` doesn't match `/copilot/`; Traefik's Prefix matched `/apiary` until strict matching was on. Test the edges on your controller.
- **A certificate that never becomes Ready.** For HTTP-01 the name must resolve to your entry point and port 80 must be reachable. For wildcards or private names, use DNS-01.
- **Exposing admin UIs.** Dashboards for Traefik, Grafana or Argo CD don't belong on the public entry point without strong auth. Use `port-forward` for admin work and audit what you expose.
- **Starting new clusters on ingress-nginx.** The community project is retired: no releases, no security patches. Pick a maintained controller.

## Clean up
From the `manifests` folder:
```bash
rm -f lab-root.crt pebble-root.pem hosts-block.txt Corefile Corefile.new converted.yaml warnings.txt
cd ..
kind delete cluster --name lab
docker rmi svc:1.0
```
If you added `*.allcsvideos.test` lines to your hosts file, remove them.

## Next
[M14-L02 · Storage](../m14-l02-storage/)
