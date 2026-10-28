# Module 13 · Practice Sheet: 25 kubectl Tasks on a Broken Cluster

It's Saturday morning, the day after allcsvideos moved to its first Kubernetes cluster. Rahul did the move last night and went to bed. His handover note:

> Everything is applied, from the files in ~/allcsvideos. kubectl get pods looked fine when I checked. But this morning the storefront doesn't open on port 30080, Meera says the course list is empty, the blog update never finished, and somebody in chat says the email password is "encrypted in a Secret, so no worries". Can you go through it all properly? Fix it in the files, not just in the cluster.

In this practice sheet you get your own copy of that cluster: a real Kubernetes v1.37 cluster made with kind, with one control-plane node and one worker, running in Docker on your machine. In it is the `allcsvideos` namespace, broken on purpose in ten different ways. You find and fix each problem with only the tools from Module 13.

**How to work:**
- You need Docker Desktop, as set up in Module 01, with about 2 GB of free memory. Nothing else is installed on your machine: kind v0.33.0 and kubectl v1.37.1 run in a tool box container, like in the Module 13 lessons.
- Do the tasks **in order**. Later tasks build on earlier fixes, exactly like a real incident: the final challenge only works once the earlier problems are fixed.
- The tasks are grouped by lesson, easy to hard: L01 and L02 the architecture, kind, kubectl, contexts and namespaces; L03 pods; L04 Deployments and ReplicaSets; L05 Services and DNS; L06 ConfigMaps and Secrets. Tasks marked **Investigate** ask you to find and explain, not only to fix. Tasks 23 to 25 are the final challenge.
- Each task has a **hint** and an **answer**. Try it yourself first. Every answer was run in this exact lab, and the output under it is the **real output** (long output is trimmed with `…`).
- Your pod names (the random endings like `-7b9f956dc4-8txjg`), IP addresses, the API server port, ages, timestamps, timings and request counts will differ. The answers say so where it matters. Everything you're asked to find (the error messages, the reasons, the fixes) is the same for everyone.
- Rahul's files are the team's repository: `~/allcsvideos`. Fix things **in the file, then apply it**, as in lesson 2. Where an answer edits a file, the sheet shows the edit as a one-line `sed`, so you can see exactly what changed. Doing the same edit in `nano` is just as good.
- In the answers, `$` is Asha's prompt in the tool box. On your screen it reads `asha@lab:~$`, and after task 1 `[kind-m13lab] asha@lab:~$`.
- All passwords in the lab are **fake demo values**, made only for this sandbox.

---

## Set up the broken cluster

**1. Save the Dockerfile.** This repository already has it: [`m13-kubernetes/Dockerfile`](m13-kubernetes/Dockerfile), so you can simply `cd practice/m13-kubernetes` and skip to step 2. (Or make an empty folder, for example `m13-lab`, and save the file below into it as `Dockerfile`.) It builds the tool box and contains the team's manifests and the script that breaks the cluster on purpose, so it **contains every answer**. Copy it without reading it.

<details>
<summary><b>Dockerfile (spoilers: copy it, don't read it)</b></summary>

```dockerfile
# syntax=docker/dockerfile:1
# DevOps course, Module 13 practice sheet: the broken cluster lab.
# A tool box with the docker CLI, kind v0.33.0 and kubectl v1.37.1 (checksums verified), the same as the Module 13 lessons.
# `lab-up` creates the kind cluster m13lab (Kubernetes v1.37.0) and deploys the allcsvideos namespace,
# BROKEN ON PURPOSE. The team's manifests are in /home/asha/allcsvideos. Reading this file spoils the tasks.
FROM docker:29.5.3-cli
ARG TARGETARCH
ARG KIND_VERSION=v0.33.0
ARG KUBECTL_VERSION=v1.37.1
ARG KIND_SHA_arm64=20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2
ARG KIND_SHA_amd64=aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d
ARG KUBECTL_SHA_arm64=ff749f4b78d9c4f1ec87307df9b50119ed819e2094aa9810cb9acffc3286c8c7
ARG KUBECTL_SHA_amd64=65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8
LABEL course=devops
RUN apk add --no-cache bash bash-completion curl jq nano less \
 && curl -fsSLo /usr/local/bin/kind https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${TARGETARCH} \
 && curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl \
 && if [ "$TARGETARCH" = arm64 ]; then KS=$KIND_SHA_arm64; CS=$KUBECTL_SHA_arm64; else KS=$KIND_SHA_amd64; CS=$KUBECTL_SHA_amd64; fi \
 && echo "$KS  /usr/local/bin/kind" | sha256sum -c - \
 && echo "$CS  /usr/local/bin/kubectl" | sha256sum -c - \
 && chmod +x /usr/local/bin/kind /usr/local/bin/kubectl \
 && adduser -D -s /bin/bash -u 1000 asha && addgroup asha root
# (the Docker Desktop socket is root:root 0660 inside containers, so asha joins group root to use it)

# ---- the cluster: one control plane, one worker; node port 30080 published on 127.0.0.1 ----
COPY <<'EOF' /opt/lab/kind-cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:        # your machine's 127.0.0.1:30080 -> node port 30080
  - containerPort: 30080
    hostPort: 30080
    listenAddress: "127.0.0.1"
    protocol: TCP
- role: worker
EOF

# ---- the team's manifests (their git repo): /home/asha/allcsvideos ----
COPY <<'EOF' /home/asha/allcsvideos/storefront.yaml
# storefront: the allcsvideos home page. nginx, plus a log-shipper sidecar, behind a NodePort Service.
apiVersion: v1
kind: ConfigMap
metadata:
  name: storefront-html
  labels: {app: storefront}
data:
  index.html: |
    <!doctype html>
    <title>allcsvideos</title>
    <h1>allcsvideos storefront</h1>
    <p>version 1.0</p>
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: storefront-nginx
  labels: {app: storefront}
data:
  default.conf: |
    server {
      listen 80;
      root /usr/share/nginx/html;
      location = /healthz { access_log off; return 200 "ok\n"; }
      # the catalog API, through the catalog Service
      location /api/ {
        proxy_pass http://catalog:80/;
        proxy_connect_timeout 3s;
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: storefront
  labels: {app: storefront, tier: frontend}
  annotations:
    kubernetes.io/change-cause: "1.0: first release on Kubernetes"
spec:
  replicas: 2
  selector:
    matchLabels: {app: storefront}
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  template:
    metadata:
      labels: {app: storefront, tier: frontend}
    spec:
      initContainers:
      - name: log-shipper              # native sidecar: follows nginx's access log
        image: busybox:1.37.0
        restartPolicy: Always
        command: ["sh", "-c", "trap 'exit 0' TERM; tail -F /var/log/nginx/access.log & wait"]
        volumeMounts: [{name: logs, mountPath: /var/log/nginx}]
      containers:
      - name: web
        image: nginx:1.29.8-alpine
        ports: [{name: http, containerPort: 80}]
        readinessProbe:
          httpGet: {path: /healthz, port: http}
          periodSeconds: 2
        resources:
          requests: {cpu: 50m, memory: 32Mi}
          limits: {memory: 64Mi}
        volumeMounts:
        - {name: html, mountPath: /usr/share/nginx/html}
        - {name: conf, mountPath: /etc/nginx/conf.d}
        - {name: logs, mountPath: /var/log/nginx}
      volumes:
      - {name: html, configMap: {name: storefront-html}}
      - {name: conf, configMap: {name: storefront-nginx}}
      - {name: logs, emptyDir: {}}
---
apiVersion: v1
kind: Service
metadata:
  name: storefront
  labels: {app: storefront}
spec:
  type: NodePort
  selector: {app: storefront}
  ports:
  - name: http
    port: 80
    targetPort: 8080
    nodePort: 30080
EOF
COPY <<'EOF' /home/asha/allcsvideos/storefront-html-v2.yaml
# storefront 2.0: the new home page. Ready to ship, not applied yet.
apiVersion: v1
kind: ConfigMap
metadata:
  name: storefront-html-v2
  labels: {app: storefront}
data:
  index.html: |
    <!doctype html>
    <title>allcsvideos</title>
    <h1>allcsvideos storefront</h1>
    <p>version 2.0: new home page with course search</p>
EOF
COPY <<'EOF' /home/asha/allcsvideos/catalog.yaml
# catalog: the course catalog API (a busybox httpd stand-in that serves courses.json on port 8080)
apiVersion: v1
kind: ConfigMap
metadata:
  name: catalog-settings
  labels: {app: catalog}
data:
  CATALOG_REGION: ap-south-1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: catalog-data
  labels: {app: catalog}
data:
  courses.json: |
    [
      {"id": "dsa", "title": "Data Structures and Algorithms"},
      {"id": "devops", "title": "DevOps: From Linux to Kubernetes in Production"}
    ]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  labels: {app: catalog, tier: backend}
spec:
  replicas: 2
  selector:
    matchLabels: {app: catalog}
  template:
    metadata:
      labels: {app: catalog-api, tier: backend}
    spec:
      containers:
      - name: catalog
        image: busybox:1.37.0
        command: ["sh", "-c", "trap 'exit 0' TERM; echo \"catalog: region $CATALOG_REGION, serving /www on port 8080\"; httpd -f -p 8080 -h /www & wait"]
        envFrom: [{configMapRef: {name: catalog-settings}}]
        ports: [{name: http, containerPort: 8080}]
        readinessProbe:
          tcpSocket: {port: http}
          periodSeconds: 2
        volumeMounts: [{name: data, mountPath: /www, readOnly: true}]
      volumes:
      - {name: data, configMap: {name: catalog-data}}
---
apiVersion: v1
kind: Service
metadata:
  name: catalog
  labels: {app: catalog}
spec:
  selector: {app: catalog, tier: api}
  ports:
  - {name: http, port: 8080, targetPort: http}
EOF
COPY <<'EOF' /home/asha/allcsvideos/copilot.yaml
# copilot: Course Copilot, a keyword-search stand-in (no AI model) on port 8080
apiVersion: apps/v1
kind: Deployment
metadata:
  name: copilot
  labels: {app: copilot, tier: backend}
spec:
  replicas: 1
  selector:
    matchLabels: {app: copilot}
  template:
    metadata:
      labels: {app: copilot, tier: backend}
    spec:
      containers:
      - name: copilot
        image: busybox:1.37.0-muscl
        command: ["sh", "-c", "mkdir -p /www && echo '{\"service\": \"course-copilot\", \"model\": \"none, keyword search only\"}' > /www/index.json && exec httpd -f -p 8080 -h /www"]
        ports: [{name: http, containerPort: 8080}]
EOF
COPY <<'EOF' /home/asha/allcsvideos/worker.yaml
# worker: the email queue worker (a stand-in: it checks its settings, then waits for jobs)
apiVersion: v1
kind: ConfigMap
metadata:
  name: worker-config
  labels: {app: worker}
data:
  QUEUE_ULR: redis://queue:6379/0
  QUEUE_NAME: emails
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  labels: {app: worker, tier: backend}
spec:
  replicas: 1
  selector:
    matchLabels: {app: worker}
  template:
    metadata:
      labels: {app: worker, tier: backend}
    spec:
      containers:
      - name: worker
        image: busybox:1.37.0
        command: ["sh", "-c", "if [ -z \"$QUEUE_URL\" ]; then echo 'worker: QUEUE_URL is not set, cannot start'; exit 1; fi; echo \"worker: consuming queue $QUEUE_NAME from $QUEUE_URL\"; exec sleep 3600"]
        envFrom: [{configMapRef: {name: worker-config}}]
EOF
COPY <<'EOF' /home/asha/allcsvideos/mailer.yaml
# mailer: sends the emails. SMTP login from the Secret mail-creds (FAKE demo values, lab only).
apiVersion: v1
kind: Secret
metadata:
  name: mail-creds
  labels: {app: mailer}
type: Opaque
stringData:
  username: mailer@example.com
  password: demo-smtp-password-123
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mailer
  labels: {app: mailer, tier: backend}
spec:
  replicas: 1
  selector:
    matchLabels: {app: mailer}
  template:
    metadata:
      labels: {app: mailer, tier: backend}
    spec:
      containers:
      - name: mailer
        image: busybox:1.37.0
        command: ["sh", "-c", "echo \"mailer: SMTP user $SMTP_USER, password read from /etc/mailer/smtp-password ($(wc -c < /etc/mailer/smtp-password) bytes)\"; exec sleep 3600"]
        env:
        - name: SMTP_USER
          valueFrom: {secretKeyRef: {name: mail-creds, key: username}}
        volumeMounts: [{name: smtp, mountPath: /etc/mailer, readOnly: true}]
      volumes:
      - name: smtp
        secret:
          secretName: mail-creds
          items:
          - {key: smtp-password, path: smtp-password}
EOF
COPY <<'EOF' /home/asha/allcsvideos/thumbnailer.yaml
# thumbnailer: makes course thumbnails. Loads a 64 MiB buffer at start (dd stands in for the image library).
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thumbnailer
  labels: {app: thumbnailer, tier: backend}
spec:
  replicas: 1
  selector:
    matchLabels: {app: thumbnailer}
  template:
    metadata:
      labels: {app: thumbnailer, tier: backend}
    spec:
      containers:
      - name: thumbnailer
        image: busybox:1.37.0
        command: ["sh", "-c", "echo 'thumbnailer: loading 64 MiB of image filters'; dd if=/dev/zero of=/dev/null bs=64M count=1 && echo 'thumbnailer: ready'; exec sleep 3600"]
        resources:
          requests: {memory: 16Mi}
          limits: {memory: 32Mi}
EOF
COPY <<'EOF' /home/asha/allcsvideos/db.yaml
# db: PostgreSQL 18 for the api. Password from the Secret db-creds (FAKE demo value, lab only).
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
  labels: {app: db}
type: Opaque
stringData:
  username: api
  password: demo-password-123
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db
  labels: {app: db, tier: data}
spec:
  replicas: 1
  selector:
    matchLabels: {app: db}
  template:
    metadata:
      labels: {app: db, tier: data}
    spec:
      containers:
      - name: postgres
        image: postgres:18.6-alpine3.24
        env:
        - name: POSTGRES_USER
          valueFrom: {secretKeyRef: {name: db-creds, key: username}}
        - name: POSTGRES_PASSWORD
          valueFrom: {secretKeyRef: {name: db-creds, key: password}}
        ports: [{name: postgres, containerPort: 5432}]
        readinessProbe:
          tcpSocket: {port: postgres}
          periodSeconds: 2
EOF
COPY <<'EOF' /home/asha/allcsvideos/api.yaml
# api: the allcsvideos API (a stand-in). It may start only once db:5432 answers.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  labels: {app: api, tier: backend}
spec:
  replicas: 1
  selector:
    matchLabels: {app: api}
  template:
    metadata:
      labels: {app: api, tier: backend}
    spec:
      initContainers:
      - name: wait-for-db
        image: busybox:1.37.0
        command: ["sh", "-c", "until nc -z -w 2 db 5432; do echo 'wait-for-db: db:5432 not reachable yet'; sleep 2; done; echo 'wait-for-db: db is up'"]
      containers:
      - name: api
        image: busybox:1.37.0
        command: ["sh", "-c", "echo 'api: db:5432 is reachable, serving'; exec sleep 3600"]
EOF
COPY <<'EOF' /home/asha/allcsvideos/blog.yaml
# blog: the allcsvideos blog (nginx)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blog
  labels: {app: blog, tier: frontend}
  annotations:
    kubernetes.io/change-cause: "1.1: run as non-root (nginx-unprivileged image)"
spec:
  replicas: 2
  progressDeadlineSeconds: 60
  selector:
    matchLabels: {app: blog}
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  template:
    metadata:
      labels: {app: blog, tier: frontend}
    spec:
      containers:
      - name: blog
        image: nginxinc/nginx-unprivileged:1.29.8-alpine
        ports: [{name: http, containerPort: 80}]
        readinessProbe:
          httpGet: {path: /, port: http}
          periodSeconds: 2
EOF

# ---- not in the repo: last week's blog, and the staging copy ----
COPY <<'EOF' /opt/lab/blog-v1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blog
  labels: {app: blog, tier: frontend}
  annotations:
    kubernetes.io/change-cause: "1.0: first release"
spec:
  replicas: 2
  selector:
    matchLabels: {app: blog}
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  template:
    metadata:
      labels: {app: blog, tier: frontend}
    spec:
      containers:
      - name: blog
        image: nginx:1.29.8-alpine
        ports: [{name: http, containerPort: 80}]
        readinessProbe:
          httpGet: {path: /, port: http}
          periodSeconds: 2
EOF
COPY <<'EOF' /opt/lab/staging.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: storefront
  labels: {app: storefront, tier: frontend}
spec:
  replicas: 2
  selector:
    matchLabels: {app: storefront}
  template:
    metadata:
      labels: {app: storefront, tier: frontend}
    spec:
      containers:
      - name: web
        image: nginx:1.29.8-alpine
        ports: [{name: http, containerPort: 80}]
EOF

# ---- lab-up: create the cluster and break it; lab-down: delete only this cluster ----
COPY --chmod=755 <<'EOF' /usr/local/bin/lab-up
#!/bin/bash
# lab-up: creates the kind cluster m13lab and deploys allcsvideos, broken on purpose. Takes 2-4 minutes.
set -euo pipefail
C=m13lab
K="kubectl --context kind-$C"
NODE_IMAGE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
if kind get clusters 2>/dev/null | grep -qx "$C"; then
  echo "The cluster $C already exists. To start over: lab-down, then lab-up."; exit 1
fi
echo "== 1/4 creating the kind cluster $C"
kind create cluster --name $C --image $NODE_IMAGE --config /opt/lab/kind-cluster.yaml --wait 120s
echo "== 2/4 deploying allcsvideos (the nodes pull the images: 1-3 minutes)"
$K create namespace allcsvideos-staging >/dev/null
$K create namespace allcsvideos >/dev/null
$K -n allcsvideos-staging apply -f /opt/lab/staging.yaml >/dev/null
cd /home/asha/allcsvideos
$K -n allcsvideos apply -f db.yaml -f api.yaml -f copilot.yaml -f worker.yaml -f mailer.yaml -f thumbnailer.yaml >/dev/null
$K -n allcsvideos apply -f catalog.yaml >/dev/null 2>&1 || true
$K -n allcsvideos apply -f storefront.yaml >/dev/null
$K -n allcsvideos apply -f /opt/lab/blog-v1.yaml >/dev/null
$K -n allcsvideos rollout status deploy/blog --timeout=300s >/dev/null
$K -n allcsvideos rollout status deploy/storefront --timeout=300s >/dev/null
$K -n allcsvideos-staging rollout status deploy/storefront --timeout=300s >/dev/null
echo "== 3/4 replaying last night's changes"
$K -n allcsvideos apply -f blog.yaml >/dev/null
$K -n allcsvideos scale deployment storefront --replicas=3 >/dev/null
$K -n allcsvideos wait --for=condition=Progressing=False deployment/blog --timeout=300s >/dev/null
$K config set-context staging --cluster kind-$C --user kind-$C --namespace allcsvideos-staging >/dev/null
$K config use-context staging >/dev/null
echo "== 4/4 the lab is ready. Start with task 1."
EOF
COPY --chmod=755 <<'EOF' /usr/local/bin/lab-down
#!/bin/bash
# lab-down: deletes the kind cluster m13lab (only this one) and the staging context
kind delete cluster --name m13lab
kubectl config delete-context staging >/dev/null 2>&1 || true
EOF

RUN chown -R asha:asha /home/asha/allcsvideos \
 && echo 'export PS1="\u@\h:\w\$ "' >> /home/asha/.bashrc \
 && echo 'source <(kubectl completion bash)' >> /home/asha/.bashrc \
 && echo '[ -f ~/.bashrc ] && . ~/.bashrc' > /home/asha/.bash_profile \
 && chown asha:asha /home/asha/.bashrc /home/asha/.bash_profile
USER asha
WORKDIR /home/asha
CMD ["sleep", "infinity"]
```

</details>

**2. Build the tool box** (a minute the first time; it downloads kind and kubectl and checks their checksums):

```bash
cd m13-lab        # in this repository: cd practice/m13-kubernetes
docker build --label course=devops -t m13lab-tools .
```

**3. Start it.** It talks to Docker Desktop through the Docker socket, so kind can create the cluster's node containers:

```bash
docker run -d --name m13lab-tools --label course=devops --hostname lab --network host \
  -v /var/run/docker.sock:/var/run/docker.sock m13lab-tools
```

**4. Create the broken cluster** with one command. It takes 2 to 4 minutes: the cluster itself takes under a minute, then the nodes pull the images and the script replays last night's changes.

```bash
docker exec -it m13lab-tools lab-up
```

It ends with `== 4/4 the lab is ready. Start with task 1.`

**5. Log in** to the tool box. Every task runs here:

```bash
docker exec -it m13lab-tools bash -l
```

A few lab notes:
- The cluster is called `m13lab`. Its nodes are two Docker containers, `m13lab-control-plane` and `m13lab-worker`. Port 30080 on your machine's `127.0.0.1` goes to node port 30080, as in lesson 2. If another lab already uses port 30080 (for example a cluster from the lessons), delete that cluster first, or `lab-up` stops with "port is already allocated".
- `kind get clusters` lists every kind cluster on your Docker Desktop, including other labs. Only `m13lab` is this one.
- The tool box has `jq`, `curl`, `nano` and kubectl's tab completion. No task needs `kubectl edit`.
- **Start over** at any time: `lab-down`, then `lab-up` again, inside the tool box. That deletes the cluster and rebuilds it broken, but your edits in `~/allcsvideos` stay. For completely fresh files too, remove the tool box and start again from step 3.
- When you're done, clean up with the commands at the end of this sheet.

---

## The tasks

### L01 and L02 · The cluster, kubectl and contexts

### 1 · Is everything really fine? (L02)

Rahul checked with `kubectl get pods` and saw two healthy storefront pods. Find out which cluster and which namespace that command was really talking to. Then switch to the right place for the real allcsvideos (the context `kind-m13lab`, namespace `allcsvideos`), make `allcsvideos` the default namespace of that context, and put the context in your prompt so this can't happen to you again.

<details>
<summary>Hint</summary>

`kubectl config current-context` names the context in use, and `kubectl config get-contexts` lists all of them, with their cluster and namespace. `use-context` switches; `set-context --current --namespace=...` sets the default namespace of the current context. Lesson 2 showed a two-line prompt: a small `kctx` function and a `PS1` that calls it.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl get pods
NAME                         READY   STATUS    RESTARTS   AGE
storefront-d57ffc9b9-pvq97   1/1     Running   0          107s
storefront-d57ffc9b9-qklng   1/1     Running   0          107s
$ kubectl config current-context
staging
$ kubectl config get-contexts
CURRENT   NAME            CLUSTER         AUTHINFO        NAMESPACE
          kind-m13lab     kind-m13lab     kind-m13lab     
*         staging         kind-m13lab     kind-m13lab     allcsvideos-staging
$ kubectl config use-context kind-m13lab
Switched to context "kind-m13lab".
$ kubectl config set-context --current --namespace=allcsvideos
Context "kind-m13lab" modified.
$ kubectl config get-contexts
CURRENT   NAME            CLUSTER         AUTHINFO        NAMESPACE
*         kind-m13lab     kind-m13lab     kind-m13lab     allcsvideos
          staging         kind-m13lab     kind-m13lab     allcsvideos-staging
$ kubectl get deployments
NAME          READY   UP-TO-DATE   AVAILABLE   AGE
api           0/1     1            0           107s
blog          2/2     1            2           105s
copilot       0/1     1            0           107s
db            1/1     1            1           107s
mailer        0/1     1            0           107s
storefront    3/3     3            3           106s
thumbnailer   0/1     1            0           107s
worker        0/1     1            0           107s
$ echo 'kctx(){ kubectl config current-context; }' >> ~/.bashrc
$ echo 'PS1="[\$(kctx)] \u@\h:\w\$ "' >> ~/.bashrc
$ tail -2 ~/.bashrc
kctx(){ kubectl config current-context; }
PS1="[\$(kctx)] \u@\h:\w\$ "
```

Open a new shell (`exec bash -l`) or `source ~/.bashrc` to get the new prompt: `[kind-m13lab] asha@lab:~$`.

**Why it works:** the current context was `staging`, and on this laptop that context points at the **same cluster** but the `allcsvideos-staging` namespace, where the staging storefront really is healthy. A context is only three names: a cluster, a user and a default namespace. `kubectl get pods` without `-n` uses that namespace, so Rahul's check was true, about the wrong place. In the real namespace, five of eight Deployments have no ready pod, and `blog` is stuck halfway through an update (UP-TO-DATE 1 of 2). The prompt now shows the context before every command, and in scripts you'd pass `--context` and `-n` explicitly.

</details>

### 2 · The control plane, for real (L01)

Show that the architecture from lesson 1 is really there. List the nodes and the pods of `kube-system` with the node each one runs on. Find the node containers in Docker, check that the kubelet and containerd on the control-plane node are **not** pods, find where the control-plane pods are defined, and ask the API server whether it's ready.

<details>
<summary>Hint</summary>

`kubectl get nodes -o wide`, `kubectl get pods -n kube-system -o wide`. kind labels its node containers with `io.x-k8s.kind.cluster=<cluster name>`, which `docker ps --filter label=...` can use. A kind node is a container, so `docker exec` reaches it (on a real server you'd use SSH): `systemctl is-active` and the folder `/etc/kubernetes/manifests`. `kubectl get --raw /readyz` calls the API directly.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl get nodes -o wide
NAME                     STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION             CONTAINER-RUNTIME
m13lab-control-plane     Ready    control-plane   2m12s   v1.37.0   172.18.0.3    <none>        Debian GNU/Linux 13 (trixie)   6.12.76-linuxkit (arm64)   containerd://2.3.4
m13lab-worker            Ready    <none>          2m1s    v1.37.0   172.18.0.2    <none>        Debian GNU/Linux 13 (trixie)   6.12.76-linuxkit (arm64)   containerd://2.3.4
$ kubectl get pods -n kube-system -o wide
NAME                                             READY   STATUS    RESTARTS   AGE     IP           NODE                     NOMINATED NODE   READINESS GATES
coredns-559f6c778d-m85gk                         1/1     Running   0          2m3s    10.244.0.4   m13lab-control-plane     <none>           <none>
coredns-559f6c778d-vldq5                         1/1     Running   0          2m3s    10.244.0.3   m13lab-control-plane     <none>           <none>
etcd-m13lab-control-plane                        1/1     Running   0          2m10s   172.18.0.3   m13lab-control-plane     <none>           <none>
kindnet-26vdk                                    1/1     Running   0          2m3s    172.18.0.3   m13lab-control-plane     <none>           <none>
kindnet-wnvmv                                    1/1     Running   0          2m1s    172.18.0.2   m13lab-worker            <none>           <none>
kube-apiserver-m13lab-control-plane              1/1     Running   0          2m10s   172.18.0.3   m13lab-control-plane     <none>           <none>
kube-controller-manager-m13lab-control-plane     1/1     Running   0          2m10s   172.18.0.3   m13lab-control-plane     <none>           <none>
kube-proxy-9xxdp                                 1/1     Running   0          2m1s    172.18.0.2   m13lab-worker            <none>           <none>
kube-proxy-bjm64                                 1/1     Running   0          2m3s    172.18.0.3   m13lab-control-plane     <none>           <none>
kube-scheduler-m13lab-control-plane              1/1     Running   0          2m10s   172.18.0.3   m13lab-control-plane     <none>           <none>
$ docker ps --filter label=io.x-k8s.kind.cluster=m13lab --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
NAMES                    IMAGE                  PORTS
m13lab-control-plane     kindest/node:v1.37.0   127.0.0.1:30080->30080/tcp, 127.0.0.1:55133->6443/tcp
m13lab-worker            kindest/node:v1.37.0   
$ docker exec m13lab-control-plane systemctl is-active kubelet containerd
active
active
$ docker exec m13lab-control-plane ls /etc/kubernetes/manifests
etcd.yaml
kube-apiserver.yaml
kube-controller-manager.yaml
kube-scheduler.yaml
$ kubectl get --raw /readyz; echo
ok
```

Your API server port (here `55133`), the IPs and the ages will differ. On a busy laptop the controller manager and the scheduler sometimes show a restart or two: they restart when they briefly lose their leader lease, and carry on.

**Why it works:** etcd, kube-apiserver, kube-controller-manager and kube-scheduler run as pods on the control-plane node, and kube-proxy plus kindnet, kind's network plugin, run on every node. CoreDNS is an add-on. The kubelet and containerd are ordinary system services on each node: they are what runs the pods, so they can't be pods themselves. The four files in `/etc/kubernetes/manifests` are static pods, started by the kubelet directly, which is how the API server can run as a pod before there is an API server. There's no cloud-controller-manager, because kind has no cloud.

</details>

### 3 · Who am I, and where is the key? (L02)

Find out how your kubectl reaches the cluster: which file holds the configuration, who can read it, which API server address it uses, as which user, and what that user is allowed to do.

<details>
<summary>Hint</summary>

The kubeconfig lives in `~/.kube/config`. `kubectl config view --minify` shows only the current context, and hides the keys. `kubectl auth whoami` and `kubectl auth can-i` ask the API server about you.

</details>

<details>
<summary>Answer</summary>

```text
$ ls -l ~/.kube/config
-rw-------    1 asha     asha          5746 Oct 21 04:24 /home/asha/.kube/config
$ kubectl config view --minify
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: DATA+OMITTED
    server: https://127.0.0.1:55133
  name: kind-m13lab
contexts:
- context:
    cluster: kind-m13lab
    namespace: allcsvideos
    user: kind-m13lab
  name: kind-m13lab
current-context: kind-m13lab
kind: Config
users:
- name: kind-m13lab
  user:
    client-certificate-data: DATA+OMITTED
    client-key-data: DATA+OMITTED
$ kubectl auth whoami
ATTRIBUTE                                           VALUE
Username                                            kubernetes-admin
Groups                                              [kubeadm:cluster-admins system:authenticated]
Extra: authentication.kubernetes.io/credential-id   [X509SHA256=78957f3f1bed062f5ffc471c6aa9c9d4862e6810bb678d36352f2a873f8b4c9c]
$ kubectl auth can-i delete nodes
Warning: resource 'nodes' is not namespace scoped

yes
$ kubectl auth can-i '*' '*' --all-namespaces
yes
```

**Why it works:** kind wrote a kubeconfig with one cluster (the API server on `127.0.0.1` and a random port, plus the CA that signs its certificate), one user (a client certificate and its private key, shown as `DATA+OMITTED`) and contexts that pair them. The API server reads your certificate: you are `kubernetes-admin` in the group `kubeadm:cluster-admins`, allowed everything, everywhere. That's why the file is mode 600, and why it must never go into chat, a ticket or git: anyone with a copy owns the cluster.

</details>

### 4 · Triage with labels (L02, L03) · Investigate

Get a first overview of the `allcsvideos` namespace. Which pods are **not** in phase Running? Then list all the backend pods with their `app` and `tier` labels as columns, and the frontend pods that aren't the blog, with all their labels. Finally list the ConfigMaps and Secrets. Explain why the filter on `phase!=Running` misses some broken pods, and what's missing from the list of Deployments.

<details>
<summary>Hint</summary>

`kubectl get all` lists the common types. `--field-selector=status.phase!=Running` filters on a field, `-l` on labels (`tier=backend`, or a set: `tier in (frontend),app!=blog`), `-L app,tier` adds label columns, and `--show-labels` prints all labels. Compare the Deployments with the files in `~/allcsvideos`.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl get all
NAME                               READY   STATUS              RESTARTS      AGE
pod/api-55858c56d6-w9r4k           0/1     Init:0/1            0             109s
pod/blog-7b9f956dc4-h7rjd          1/1     Running             0             107s
pod/blog-7b9f956dc4-mb6sn          1/1     Running             0             107s
pod/blog-86d5488fc4-h9tz5          0/1     Running             0             63s
pod/copilot-855b5cc7db-4bpqp       0/1     ImagePullBackOff    0             109s
pod/db-57c4984f5-5fz2m             1/1     Running             0             109s
pod/mailer-9c66dc4d6-j4s4k         0/1     ContainerCreating   0             109s
pod/storefront-578c4b7969-2jsrx    2/2     Running             0             108s
pod/storefront-578c4b7969-4p9pm    2/2     Running             0             63s
pod/storefront-578c4b7969-5846p    2/2     Running             0             108s
pod/thumbnailer-5687647677-67vhg   0/1     OOMKilled           3 (54s ago)   109s
pod/worker-5846c67d66-mkzd8        0/1     Error               3 (53s ago)   109s

NAME                 TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
service/catalog      ClusterIP   10.96.119.83   <none>        8080/TCP       108s
service/storefront   NodePort    10.96.235.50   <none>        80:30080/TCP   108s

NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/api           0/1     1            0           109s
deployment.apps/blog          2/2     1            2           107s
deployment.apps/copilot       0/1     1            0           109s
deployment.apps/db            1/1     1            1           109s
deployment.apps/mailer        0/1     1            0           109s
deployment.apps/storefront    3/3     3            3           108s
deployment.apps/thumbnailer   0/1     1            0           109s
deployment.apps/worker        0/1     1            0           109s

NAME                                     DESIRED   CURRENT   READY   AGE
replicaset.apps/api-55858c56d6           1         1         0       109s
replicaset.apps/blog-7b9f956dc4          2         2         2       107s
replicaset.apps/blog-86d5488fc4          1         1         0       63s
replicaset.apps/copilot-855b5cc7db       1         1         0       109s
replicaset.apps/db-57c4984f5             1         1         1       109s
replicaset.apps/mailer-9c66dc4d6         1         1         0       109s
replicaset.apps/storefront-578c4b7969    3         3         3       108s
replicaset.apps/thumbnailer-5687647677   1         1         0       109s
replicaset.apps/worker-5846c67d66        1         1         0       109s
$ kubectl get pods --field-selector=status.phase!=Running
NAME                       READY   STATUS              RESTARTS   AGE
api-55858c56d6-w9r4k       0/1     Init:0/1            0          109s
copilot-855b5cc7db-4bpqp   0/1     ImagePullBackOff    0          109s
mailer-9c66dc4d6-j4s4k     0/1     ContainerCreating   0          109s
$ kubectl get pods -l tier=backend -L app,tier
NAME                           READY   STATUS              RESTARTS      AGE    APP           TIER
api-55858c56d6-w9r4k           0/1     Init:0/1            0             109s   api           backend
copilot-855b5cc7db-4bpqp       0/1     ImagePullBackOff    0             109s   copilot       backend
mailer-9c66dc4d6-j4s4k         0/1     ContainerCreating   0             109s   mailer        backend
thumbnailer-5687647677-67vhg   0/1     OOMKilled           3 (54s ago)   109s   thumbnailer   backend
worker-5846c67d66-mkzd8        0/1     Error               3 (53s ago)   109s   worker        backend
$ kubectl get pods -l 'tier in (frontend),app!=blog' --show-labels
NAME                          READY   STATUS    RESTARTS   AGE    LABELS
storefront-578c4b7969-2jsrx   2/2     Running   0          108s   app=storefront,pod-template-hash=578c4b7969,tier=frontend
storefront-578c4b7969-4p9pm   2/2     Running   0          63s    app=storefront,pod-template-hash=578c4b7969,tier=frontend
storefront-578c4b7969-5846p   2/2     Running   0          108s   app=storefront,pod-template-hash=578c4b7969,tier=frontend
$ kubectl get configmaps,secrets
NAME                         DATA   AGE
configmap/catalog-data       1      108s
configmap/catalog-settings   1      108s
configmap/kube-root-ca.crt   1      110s
configmap/storefront-html    1      108s
configmap/storefront-nginx   1      108s
configmap/worker-config      2      109s

NAME                TYPE     DATA   AGE
secret/db-creds     Opaque   2      109s
secret/mail-creds   Opaque   2      109s
```

Your restart counts and ages differ, and the STATUS of the two crashing pods flips between `Error`, `OOMKilled` and `CrashLoopBackOff` from second to second.

**What it shows:** three pods are Pending: `api` is stuck in its init container, `copilot` can't pull its image, `mailer` can't even create its container. But `thumbnailer` and `worker` are just as broken, and their phase is **Running**: a pod stays Running while its container keeps restarting. The phase is only a summary. The READY column, the restarts and the container's reason tell the truth (task 7). And there's no `catalog` Deployment at all, although its ConfigMaps and its Service exist: `~/allcsvideos/catalog.yaml` was only half applied (task 13).

</details>

### 5 · The built-in manual (L02)

Without leaving the terminal, answer four questions: what are the short names of ConfigMaps, Services and ReplicaSets, and which of the resource types here are not namespaced? How long may a Deployment take to make progress before it counts as failed, by default? How long does a pod get to shut down, by default? And what may a Service's `targetPort` be: a number, a name, or both?

<details>
<summary>Hint</summary>

`kubectl api-resources` lists every type with its short name and whether it's namespaced. `kubectl explain` prints the documentation of any field, for example `deployment.spec.progressDeadlineSeconds`.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl api-resources | grep -E '^NAME|^(configmaps|endpointslices|namespaces|nodes|pods|replicasets|secrets|services) '
NAME                                SHORTNAMES   APIVERSION                        NAMESPACED   KIND
configmaps                          cm           v1                                true         ConfigMap
namespaces                          ns           v1                                false        Namespace
nodes                               no           v1                                false        Node
pods                                po           v1                                true         Pod
secrets                                          v1                                true         Secret
services                            svc          v1                                true         Service
replicasets                         rs           apps/v1                           true         ReplicaSet
endpointslices                                   discovery.k8s.io/v1               true         EndpointSlice
$ kubectl explain deployment.spec.progressDeadlineSeconds
GROUP:      apps
KIND:       Deployment
VERSION:    v1

FIELD: progressDeadlineSeconds <integer>


DESCRIPTION:
    The maximum time in seconds for a deployment to make progress before it is
    considered to be failed. The deployment controller will continue to process
    failed deployments and a condition with a ProgressDeadlineExceeded reason
    will be surfaced in the deployment status. Note that progress will not be
    estimated during the time a deployment is paused. Defaults to 600s.
    

$ kubectl explain pod.spec.terminationGracePeriodSeconds | grep -E 'FIELD|Defaults'
FIELD: terminationGracePeriodSeconds <integer>
    cleanup time for your process. Defaults to 30 seconds.
$ kubectl explain service.spec.ports.targetPort
KIND:       Service
VERSION:    v1

FIELD: targetPort <IntOrString>


DESCRIPTION:
    Number or name of the port to access on the pods targeted by the service.
    Number must be in the range 1 to 65535. Name must be an IANA_SVC_NAME. If
    this is a string, it will be looked up as a named port in the target Pod's
    container ports. If this is not specified, the value of the 'port' field is
    used (an identity map). This field is ignored for services with
    clusterIP=None, and should be omitted or set equal to the 'port' field. More
    info:
    https://kubernetes.io/docs/concepts/services-networking/service/#defining-a-service
    IntOrString is a type that can hold an int32 or a string.  When used in JSON
    or YAML marshalling and unmarshalling, it produces or consumes the inner
    type.  This allows you to have, for example, a JSON field that can accept a
    name or number.
    
```

**The answers:** `cm`, `svc` and `rs` (Secrets and EndpointSlices have no short name); nodes and namespaces are cluster-wide, not namespaced. A Deployment gets 600 seconds without progress by default, and `blog` sets its own (task 16). A pod gets 30 seconds between SIGTERM and SIGKILL (task 12). And `targetPort` is an IntOrString: a number, or the **name** of a container port, which keeps the Service right even when the port number changes (task 23).

</details>

### 6 · Drift (L02)

Someone changed the live storefront by hand last night. Find out what is different between the cluster and `~/allcsvideos/storefront.yaml`, without changing anything. Then make the cluster match the file again, and prove that nothing is different any more.

<details>
<summary>Hint</summary>

`kubectl diff -f FILE` compares the live objects with what the file would make them, and exits with 1 when there's a difference and 0 when there's none. Then `kubectl apply -f`.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/allcsvideos
$ ls
api.yaml
blog.yaml
catalog.yaml
copilot.yaml
db.yaml
mailer.yaml
storefront-html-v2.yaml
storefront.yaml
thumbnailer.yaml
worker.yaml
$ kubectl get deployment storefront
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
storefront   3/3     3            3           109s
$ kubectl diff -f storefront.yaml; echo "exit code: $?"
--- /tmp/LIVE-731004229/apps.v1.Deployment.allcsvideos.storefront
+++ /tmp/MERGED-3326702719/apps.v1.Deployment.allcsvideos.storefront
@@ -7,7 +7,7 @@
       {"apiVersion":"apps/v1","kind":"Deployment", …}
     kubernetes.io/change-cause: '1.0: first release on Kubernetes'
   creationTimestamp: "2026-10-21T04:22:31Z"
-  generation: 2
+  generation: 3
   labels:
     app: storefront
     tier: frontend
@@ -17,7 +17,7 @@
   uid: 77f0ea42-e438-4706-b333-e29a1434765f
 spec:
   progressDeadlineSeconds: 600
-  replicas: 3
+  replicas: 2
   revisionHistoryLimit: 10
   selector:
     matchLabels:
exit code: 1
$ kubectl apply -f storefront.yaml
configmap/storefront-html unchanged
configmap/storefront-nginx unchanged
deployment.apps/storefront configured
service/storefront unchanged
$ kubectl rollout status deployment storefront
deployment "storefront" successfully rolled out
$ kubectl diff -f storefront.yaml; echo "exit code: $?"
exit code: 0
```

**Why it works:** `kubectl diff` sends the file to the API server as a dry run and compares the result with the live object: the file says 2 replicas, the cluster runs 3. Someone ran `kubectl scale` (lesson 2's drift). The long line at the top is the `last-applied-configuration` annotation, the copy of the file that apply keeps. After the apply, the Deployment controller scaled the ReplicaSet back to 2, and `diff` prints nothing with exit code 0. That exit code is what a pipeline would check.

</details>

---

### L03 · Pods

### 7 · Phase versus state (L03) · Investigate

Build one table of every pod in the namespace with its phase, the reason its container is waiting, the reason its last run ended, and its restart count. Explain why `api` and `mailer` are Pending while `thumbnailer` is Running.

<details>
<summary>Hint</summary>

`-o custom-columns='NAME:path,…'` with paths like `.status.phase`, `.status.containerStatuses[*].state.waiting.reason`, `.status.containerStatuses[*].lastState.terminated.reason` and `.status.containerStatuses[*].restartCount`.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl get pods -o custom-columns='POD:.metadata.name,PHASE:.status.phase,WAITING:.status.containerStatuses[*].state.waiting.reason,LAST-EXIT:.status.containerStatuses[*].lastState.terminated.reason,RESTARTS:.status.containerStatuses[*].restartCount'
POD                            PHASE       WAITING             LAST-EXIT   RESTARTS
api-55858c56d6-w9r4k           Pending     PodInitializing     <none>      0
blog-7b9f956dc4-h7rjd          Running     <none>              <none>      0
blog-7b9f956dc4-mb6sn          Running     <none>              <none>      0
blog-86d5488fc4-h9tz5          Running     <none>              <none>      0
copilot-855b5cc7db-4bpqp       Pending     ImagePullBackOff    <none>      0
db-57c4984f5-5fz2m             Running     <none>              <none>      0
mailer-9c66dc4d6-j4s4k         Pending     ContainerCreating   <none>      0
storefront-578c4b7969-2jsrx    Running     <none>              <none>      0
storefront-578c4b7969-4p9pm    Succeeded   <none>              <none>      0
storefront-578c4b7969-5846p    Running     <none>              <none>      0
thumbnailer-5687647677-67vhg   Running     <none>              OOMKilled   3
worker-5846c67d66-mkzd8        Running     <none>              Error       3
```

The WAITING column of the two crashing pods changes over time: `CrashLoopBackOff` while the kubelet waits before the next try, `<none>` in the moment a try runs. The storefront pod in phase `Succeeded` is the one task 6 just scaled away: while it shut down, both its containers exited cleanly with 0, and it disappears a moment later.

**What it shows:** Pending means "accepted, but not running yet": `api` is still in its init container (`PodInitializing`), `copilot` waits for an image, `mailer` for its volume. `thumbnailer` and `worker` did start, so their phase is Running, even though each run ends at once: `OOMKilled` and `Error`. The phase sums up the pod, the container states explain it. The other Running pods with nothing waiting are healthy, except `blog`'s third pod, which runs but is never ready (task 16): READY is a separate condition from the phase.

</details>

### 8 · ImagePullBackOff (L03)

Course Copilot never starts. Find the exact reason in the pod's events, fix it in `copilot.yaml`, and prove the service answers.

<details>
<summary>Hint</summary>

When a pod misbehaves, read the events first: the bottom of `kubectl describe pod`. `kubectl diff` before `apply` shows exactly what you changed. busybox's `wget -qO-` fetches a page from inside the pod.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl get pods -l app=copilot
NAME                       READY   STATUS             RESTARTS   AGE
copilot-855b5cc7db-4bpqp   0/1     ImagePullBackOff   0          112s
$ kubectl describe pod -l app=copilot | sed -n '/^Events:/,$p'
Events:
  Type     Reason            Age                 From               Message
  ----     ------            ----                ----               -------
  Warning  FailedScheduling  112s                default-scheduler  0/2 nodes are available: 2 node(s) had untolerated taint(s). preemption: 0/2 nodes are available: 2 Preemption is not helpful for scheduling.
  Normal   Scheduled         111s                default-scheduler  Successfully assigned allcsvideos/copilot-855b5cc7db-4bpqp to m13lab-worker
  Normal   Pulling           40s (x3 over 109s)  kubelet            spec.containers{copilot}: Pulling image "busybox:1.37.0-muscl"
  Warning  Failed            38s (x3 over 99s)   kubelet            spec.containers{copilot}: Failed to pull image "busybox:1.37.0-muscl": rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/library/busybox:1.37.0-muscl": failed to resolve reference "docker.io/library/busybox:1.37.0-muscl": docker.io/library/busybox:1.37.0-muscl: not found
  Warning  Failed            38s (x3 over 99s)   kubelet            spec.containers{copilot}: Error: ErrImagePull
  Normal   BackOff           10s (x4 over 99s)   kubelet            spec.containers{copilot}: Back-off pulling image "busybox:1.37.0-muscl"
  Warning  Failed            10s (x4 over 99s)   kubelet            spec.containers{copilot}: Error: ImagePullBackOff
$ cd ~/allcsvideos
$ grep -n 'image:' copilot.yaml
17:        image: busybox:1.37.0-muscl
$ sed -i 's/busybox:1.37.0-muscl/busybox:1.37.0/' copilot.yaml
$ kubectl diff -f copilot.yaml | grep '^[-+] '
-  generation: 1
+  generation: 2
-        image: busybox:1.37.0-muscl
+        image: busybox:1.37.0
$ kubectl apply -f copilot.yaml
deployment.apps/copilot configured
$ kubectl rollout status deployment copilot
Waiting for deployment "copilot" rollout to finish: 1 old replicas are pending termination...
deployment "copilot" successfully rolled out
$ kubectl get pods -l app=copilot
NAME                       READY   STATUS        RESTARTS   AGE
copilot-6d8dbfb697-sqfgp   1/1     Running       0          1s
copilot-855b5cc7db-4bpqp   0/1     Terminating   0          114s
$ kubectl exec deploy/copilot -- wget -qO- 127.0.0.1:8080/index.json
{"service": "course-copilot", "model": "none, keyword search only"}
```

**Why it works:** the tag `1.37.0-muscl` doesn't exist on Docker Hub (the real one is `1.37.0-musl`; `1.37.0` is the one the rest of the lab uses). The kubelet tried, failed with `ErrImagePull`, and backs off longer and longer between tries: `ImagePullBackOff`. Fixing the template created a new ReplicaSet, and the old pod went away. The first event, `FailedScheduling`, is from the first seconds of the cluster: the worker wasn't Ready yet, and the control plane has a NoSchedule taint.

</details>

### 9 · OOMKilled (L03)

The thumbnailer restarts again and again. Find out what kills it, with its exit code, and fix it in `thumbnailer.yaml`.

<details>
<summary>Hint</summary>

`describe` shows the container's `Last State` and its `Limits`. `kubectl logs` of a crashed container prints the output of its last run. Exit code 137 is 128 plus signal 9.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl get pods -l app=thumbnailer
NAME                           READY   STATUS      RESTARTS      AGE
thumbnailer-5687647677-67vhg   0/1     OOMKilled   3 (60s ago)   115s
$ kubectl describe pod -l app=thumbnailer | sed -n '/^    State:/,/^    Ready:/p;/Limits:/,/memory:/p'
    State:          Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Wed, 21 Oct 2026 04:23:53 +0000
      Finished:     Wed, 21 Oct 2026 04:23:53 +0000
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Wed, 21 Oct 2026 04:23:24 +0000
      Finished:     Wed, 21 Oct 2026 04:23:25 +0000
    Ready:          False
    Limits:
      memory:  32Mi
$ kubectl get pod -l app=thumbnailer -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated}' | jq '{reason, exitCode}'
{
  "reason": "OOMKilled",
  "exitCode": 137
}
$ kubectl logs deploy/thumbnailer
thumbnailer: loading 64 MiB of image filters
$ cd ~/allcsvideos
$ sed -i 's/limits: {memory: 32Mi}/limits: {memory: 128Mi}/; s/requests: {memory: 16Mi}/requests: {memory: 96Mi}/' thumbnailer.yaml
$ grep -A2 'resources:' thumbnailer.yaml
        resources:
          requests: {memory: 96Mi}
          limits: {memory: 128Mi}
$ kubectl apply -f thumbnailer.yaml
deployment.apps/thumbnailer configured
$ kubectl rollout status deployment thumbnailer
Waiting for deployment "thumbnailer" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "thumbnailer" rollout to finish: 1 old replicas are pending termination...
deployment "thumbnailer" successfully rolled out
$ kubectl get pods -l app=thumbnailer
NAME                           READY   STATUS        RESTARTS      AGE
thumbnailer-5687647677-67vhg   0/1     Terminating   3 (62s ago)   117s
thumbnailer-868fd49549-vmjcn   1/1     Running       0             2s
$ sleep 3; kubectl logs deploy/thumbnailer
thumbnailer: loading 64 MiB of image filters
1+0 records in
1+0 records out
67108864 bytes (64.0MB) copied, 0.438586 seconds, 145.9MB/s
thumbnailer: ready
```

**Why it works:** the app loads a 64 MiB buffer at start, but its memory limit was 32 MiB. The kernel's OOM killer kills the process inside its cgroup with SIGKILL (137 = 128 + 9), the kubelet restarts it, and it dies again: `OOMKilled`, then `CrashLoopBackOff`. A limit must be above what the app really needs, and the request close to its normal use: here a request of 96 MiB and a limit of 128 MiB. Module 14 covers sizing in depth.

</details>

### 10 · Stuck in Init (L03, L05)

The API has said `Init:0/1` since last night. Find out what its init container is waiting for, and give it what it needs, as a file in the repository.

<details>
<summary>Hint</summary>

`kubectl logs <pod> -c <init container>` reads an init container's output. `nc: bad address` means the name doesn't resolve at all. `kubectl expose deployment ... --dry-run=client -o yaml > file` writes a Service manifest without creating it.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl get pods -l app=api
NAME                   READY   STATUS     RESTARTS   AGE
api-55858c56d6-w9r4k   0/1     Init:0/1   0          2m
$ kubectl logs deploy/api -c wait-for-db --tail=3
wait-for-db: db:5432 not reachable yet
nc: bad address 'db'
wait-for-db: db:5432 not reachable yet
$ kubectl get svc
NAME         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
catalog      ClusterIP   10.96.119.83   <none>        8080/TCP       2m
storefront   NodePort    10.96.235.50   <none>        80:30080/TCP   2m
$ kubectl get pods -l app=db --show-labels
NAME                 READY   STATUS    RESTARTS   AGE    LABELS
db-57c4984f5-5fz2m   1/1     Running   0          2m1s   app=db,pod-template-hash=57c4984f5,tier=data
$ cd ~/allcsvideos
$ kubectl expose deployment db --port=5432 --target-port=postgres --dry-run=client -o yaml > db-service.yaml
$ cat db-service.yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: db
    tier: data
  name: db
spec:
  ports:
  - port: 5432
    protocol: TCP
    targetPort: postgres
  selector:
    app: db
status:
  loadBalancer: {}
$ kubectl apply -f db-service.yaml
service/db created
$ kubectl get endpointslices -l kubernetes.io/service-name=db
NAME       ADDRESSTYPE   PORTS   ENDPOINTS    AGE
db-tb2qr   IPv4          5432    10.244.1.7   0s
$ kubectl wait --for=condition=Ready pod -l app=api --timeout=60s
pod/api-55858c56d6-w9r4k condition met
$ kubectl logs deploy/api -c wait-for-db --tail=2
wait-for-db: db:5432 not reachable yet
wait-for-db: db is up
$ kubectl logs deploy/api
Defaulted container "api" out of: api, wait-for-db (init)
api: db:5432 is reachable, serving
```

**Why it works:** the init container loops until `nc -z db 5432` succeeds, and app containers start only after every init container has exited successfully. The PostgreSQL pod was running all along, but nobody created a Service called `db`, so the name didn't exist. `expose` built one from the Deployment's own selector, `app: db`, and `targetPort: postgres` uses the container's named port. Within seconds the EndpointSlice listed the pod, the init container got through and exited, and the API started.

</details>

### 11 · The sidecar (L03)

The storefront pods show `2/2`. Find out what the second container is, prove that it's a native sidecar, and show that the two containers share files but not their filesystems: make two requests to nginx, and read them from the other container.

<details>
<summary>Hint</summary>

`-o jsonpath` on `.spec.initContainers` and `.spec.containers`. A native sidecar is an init container with `restartPolicy: Always`. `kubectl exec <pod> -c web` and `kubectl logs <pod> -c log-shipper` pick a container. Use one pod name for both, not `deploy/storefront`, which may pick a different pod each time.

</details>

<details>
<summary>Answer</summary>

```text
$ P=$(kubectl get pods -l app=storefront -o jsonpath='{.items[0].metadata.name}'); echo $P
storefront-578c4b7969-2jsrx
$ kubectl get pod $P
NAME                          READY   STATUS    RESTARTS   AGE
storefront-578c4b7969-2jsrx   2/2     Running   0          2m3s
$ kubectl get pod $P -o jsonpath='init: {.spec.initContainers[*].name} (restartPolicy {.spec.initContainers[0].restartPolicy}){"\n"}app:  {.spec.containers[*].name}{"\n"}'
init: log-shipper (restartPolicy Always)
app:  web
$ kubectl get pod $P -o jsonpath='{.status.podIP}{"\n"}'
10.244.1.8
$ kubectl exec $P -c web -- wget -qO /dev/null 127.0.0.1/
$ kubectl exec $P -c web -- wget -qO /dev/null 127.0.0.1/courses
wget: server returned error: HTTP/1.1 404 Not Found
command terminated with exit code 1
$ sleep 1; kubectl logs $P -c log-shipper --tail=2
127.0.0.1 - - [21/Oct/2026:04:24:34 +0000] "GET / HTTP/1.1" 200 94 "-" "Wget" "-"
127.0.0.1 - - [21/Oct/2026:04:24:35 +0000] "GET /courses HTTP/1.1" 404 153 "-" "Wget" "-"
$ kubectl exec $P -c log-shipper -- ls -l /var/log/nginx
total 8
-rw-r--r--    1 root     root           172 Oct 21 04:24 access.log
-rw-r--r--    1 root     root          1161 Oct 21 04:24 error.log
$ kubectl exec $P -c log-shipper -- ls /usr/share/nginx
ls: /usr/share/nginx: No such file or directory
command terminated with exit code 1
```

**Why it works:** `log-shipper` is listed under `initContainers` with `restartPolicy: Always`, so it starts before nginx, keeps running beside it for the pod's whole life, and counts in READY. Both containers mount the same `emptyDir` volume at `/var/log/nginx`, so the access log nginx writes is the file the sidecar follows. But each container keeps its own filesystem: `/usr/share/nginx` exists only in the nginx container.

</details>

### 12 · Why does delete take 30 seconds? (L03) · Investigate

Delete the Copilot pod and time it. Explain why it takes about 30 seconds, why the pod is back anyway, and show with a small test pod how an app that handles SIGTERM shuts down at once.

<details>
<summary>Hint</summary>

`time kubectl delete pod ...`. `ps` inside the container shows PID 1. The kernel never applies a signal's default action to PID 1 in a container: a process that doesn't handle SIGTERM ignores it there. `kubectl run NAME --image=... --restart=Never -- sh -c "..."` starts a bare test pod; `trap '...' TERM` handles the signal in a shell.

</details>

<details>
<summary>Answer</summary>

```text
$ P=$(kubectl get pods -l app=copilot -o name); echo $P
pod/copilot-6d8dbfb697-sqfgp
$ time kubectl delete $P
pod "copilot-6d8dbfb697-sqfgp" deleted from allcsvideos namespace

real	0m30.655s
user	0m0.066s
sys	0m0.018s
$ kubectl get pods -l app=copilot
NAME                       READY   STATUS    RESTARTS   AGE
copilot-6d8dbfb697-7q8fd   1/1     Running   0          30s
$ kubectl exec deploy/copilot -- ps -o pid,args
PID   COMMAND
    1 httpd -f -p 8080 -h /www
   12 ps -o pid,args
$ kubectl get deploy copilot -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}{"\n"}'
30
$ kubectl get events --field-selector involvedObject.name=${P#pod/}
LAST SEEN   TYPE     REASON      OBJECT                         MESSAGE
44s         Normal   Scheduled   pod/copilot-6d8dbfb697-sqfgp   Successfully assigned allcsvideos/copilot-6d8dbfb697-sqfgp to m13lab-worker
44s         Normal   Pulled      pod/copilot-6d8dbfb697-sqfgp   Container image "busybox:1.37.0" already present on machine and can be accessed by the pod
44s         Normal   Created     pod/copilot-6d8dbfb697-sqfgp   Container created
44s         Normal   Started     pod/copilot-6d8dbfb697-sqfgp   Container started
30s         Normal   Killing     pod/copilot-6d8dbfb697-sqfgp   Stopping container copilot
$ kubectl run trap-test --image=busybox:1.37.0 --restart=Never -- sh -c "trap 'echo got SIGTERM, bye; exit 0' TERM; while true; do sleep 1; done"
pod/trap-test created
$ kubectl wait --for=condition=Ready pod/trap-test --timeout=60s
pod/trap-test condition met
$ time kubectl delete pod trap-test
pod "trap-test" deleted from allcsvideos namespace

real	0m1.198s
user	0m0.050s
sys	0m0.014s
```

**Why it works:** kubectl delete marks the pod Terminating, and the kubelet sends SIGTERM to PID 1 in each container. Here PID 1 is busybox `httpd`, which installs no SIGTERM handler, and as PID 1 it simply ignores the signal. So the kubelet waits the whole grace period, 30 seconds by default, then sends SIGKILL. The `Killing` event marks the start. The pod came back because its ReplicaSet saw one pod missing and created a new one in the same second (lesson 4). The test pod handles SIGTERM and exits, so its delete took about a second. Fix the app, not the grace period: handle SIGTERM, or let a real init process forward it.

</details>

---

### L04 · Deployments and ReplicaSets

### 13 · The Deployment that never existed (L04)

`kubectl get deployment catalog` finds nothing, although `catalog.yaml` is in the repository. Apply it, read the error, and fix the file so the catalog runs with 2 replicas.

<details>
<summary>Hint</summary>

The API server refuses a Deployment whose `selector` can't find its own pods. Compare `spec.selector.matchLabels` with `spec.template.metadata.labels`. Fix the template's labels, so the selector stays `app: catalog`.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/allcsvideos
$ kubectl get deployment catalog
Error from server (NotFound): deployments.apps "catalog" not found
$ kubectl apply -f catalog.yaml
configmap/catalog-settings unchanged
configmap/catalog-data unchanged
service/catalog unchanged
The Deployment "catalog" is invalid: spec.template.metadata.labels: Invalid value: {"app":"catalog-api","tier":"backend"}: `selector` does not match template `labels`
$ grep -n -A1 -E 'matchLabels|^    metadata' catalog.yaml
30:    matchLabels: {app: catalog}
31-  template:
32:    metadata:
33-      labels: {app: catalog-api, tier: backend}
$ sed -i 's/labels: {app: catalog-api, tier: backend}/labels: {app: catalog, tier: backend}/' catalog.yaml
$ kubectl apply -f catalog.yaml
configmap/catalog-settings unchanged
configmap/catalog-data unchanged
deployment.apps/catalog created
service/catalog unchanged
$ kubectl rollout status deployment catalog
Waiting for deployment "catalog" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "catalog" rollout to finish: 1 of 2 updated replicas are available...
deployment "catalog" successfully rolled out
$ kubectl get deploy,rs,pods -l app=catalog
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/catalog   2/2     2            2           1s

NAME                               DESIRED   CURRENT   READY   AGE
replicaset.apps/catalog-c8d6c688   2         2         2       1s

NAME                         READY   STATUS    RESTARTS   AGE
pod/catalog-c8d6c688-dbkn9   1/1     Running   0          1s
pod/catalog-c8d6c688-zxb7v   1/1     Running   0          1s
$ kubectl logs deploy/catalog
Found 2 pods, using pod/catalog-c8d6c688-dbkn9
catalog: region ap-south-1, serving /www on port 8080
```

**Why it works:** `kubectl apply` applies each object in the file on its own: the ConfigMaps and the Service went in last night, and only the Deployment was rejected. Its selector said `app: catalog`, its pods would have been `app: catalog-api`, and a Deployment that could never find its own pods is invalid. With matching labels, the Deployment created a ReplicaSet, and the ReplicaSet two pods. Plan labels before the first apply: once a Deployment exists, its selector is immutable.

</details>

### 14 · Who owns this pod? (L04)

Prove the ownership chain of a catalog pod, all the way up to the Deployment. Then delete the pod, and try to scale its ReplicaSet to 4 directly. Explain both results.

<details>
<summary>Hint</summary>

Every pod and ReplicaSet records its owner in `metadata.ownerReferences`. `jq` (installed in the tool box) can pick fields: `jq '{kind, name, controller}'`. `kubectl scale rs NAME --replicas=4`.

</details>

<details>
<summary>Answer</summary>

```text
$ P=$(kubectl get pods -l app=catalog -o jsonpath='{.items[0].metadata.name}'); echo $P
catalog-c8d6c688-dbkn9
$ kubectl get pod $P -o jsonpath='{.metadata.ownerReferences[0]}' | jq '{kind, name, controller}'
{
  "kind": "ReplicaSet",
  "name": "catalog-c8d6c688",
  "controller": true
}
$ RS=$(kubectl get pod $P -o jsonpath='{.metadata.ownerReferences[0].name}'); echo $RS
catalog-c8d6c688
$ kubectl get rs $RS -o jsonpath='{.metadata.ownerReferences[0]}' | jq '{kind, name, controller}'
{
  "kind": "Deployment",
  "name": "catalog",
  "controller": true
}
$ kubectl delete pod $P
pod "catalog-c8d6c688-dbkn9" deleted from allcsvideos namespace
$ kubectl get pods -l app=catalog
NAME                     READY   STATUS    RESTARTS   AGE
catalog-c8d6c688-cgdcv   1/1     Running   0          3s
catalog-c8d6c688-zxb7v   1/1     Running   0          4s
$ kubectl scale rs $RS --replicas=4
replicaset.apps/catalog-c8d6c688 scaled
$ sleep 2; kubectl get rs $RS
NAME               DESIRED   CURRENT   READY   AGE
catalog-c8d6c688   2         2         2       6s
$ kubectl get pods -l app=catalog
NAME                     READY   STATUS    RESTARTS   AGE
catalog-c8d6c688-cgdcv   1/1     Running   0          5s
catalog-c8d6c688-zxb7v   1/1     Running   0          6s
```

**Why it works:** the pod's owner is a ReplicaSet and the ReplicaSet's owner is the Deployment, both with `controller: true`. When the pod was deleted, the ReplicaSet controller saw one of two pods missing and created a replacement at once (2 seconds old when we looked). The direct scale to 4 was accepted, then undone within the same second: the Deployment says 2, so the deployment controller set its ReplicaSet back. Every change goes through the Deployment.

</details>

### 15 · Scale it the declarative way (L04)

The catalog needs 3 replicas from now on. Make the change so that the repository and the cluster agree, preview it first, and check whether scaling created a new ReplicaSet.

<details>
<summary>Hint</summary>

Edit `replicas` in `catalog.yaml`, then `kubectl diff`, then `kubectl apply`. `kubectl scale` would work too, but leave the file saying 2: that's the drift of task 6.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/allcsvideos
$ kubectl get rs -l app=catalog
NAME               DESIRED   CURRENT   READY   AGE
catalog-c8d6c688   2         2         2       7s
$ sed -i 's/replicas: 2/replicas: 3/' catalog.yaml
$ kubectl diff -f catalog.yaml | grep '^[-+] '
-  generation: 1
+  generation: 2
-  replicas: 2
+  replicas: 3
$ kubectl apply -f catalog.yaml
configmap/catalog-settings unchanged
configmap/catalog-data unchanged
deployment.apps/catalog configured
service/catalog unchanged
$ kubectl rollout status deployment catalog
Waiting for deployment "catalog" rollout to finish: 2 of 3 updated replicas are available...
deployment "catalog" successfully rolled out
$ kubectl get rs -l app=catalog
NAME               DESIRED   CURRENT   READY   AGE
catalog-c8d6c688   3         3         3       7s
$ kubectl diff -f catalog.yaml; echo "exit code: $?"
exit code: 0
```

**Why it works:** only the replica count changed, not the pod template, so the Deployment kept the same ReplicaSet (same hash, `c8d6c688` here) and just asked it for one more pod. Only a template change creates a new ReplicaSet. And because the change is in the file, the next apply keeps it, and `diff` exits with 0.

</details>

### 16 · The rollout that never finished (L04) · Investigate

Last night Rahul applied the blog's version 1.1. `kubectl rollout status` for `blog` fails. Find out what state the rollout is in, why the new pod is never ready, roll back to the working version, and then fix version 1.1 properly in `blog.yaml`, so the repository works again.

<details>
<summary>Hint</summary>

The Deployment's conditions say whether it's `Progressing` and why. Find the pod that isn't ready, read its readiness probe and its `Unhealthy` events, and check which port nginx really listens on in the new image (`/etc/nginx/conf.d/default.conf`). `kubectl rollout history` and `kubectl rollout undo` go back. Then make the container port in the file match.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl rollout status deployment blog --timeout=10s
error: deployment "blog" exceeded its progress deadline
$ kubectl get rs,pods -l app=blog
NAME                              DESIRED   CURRENT   READY   AGE
replicaset.apps/blog-7b9f956dc4   2         2         2       2m46s
replicaset.apps/blog-86d5488fc4   1         1         0       2m2s

NAME                        READY   STATUS    RESTARTS   AGE
pod/blog-7b9f956dc4-h7rjd   1/1     Running   0          2m46s
pod/blog-7b9f956dc4-mb6sn   1/1     Running   0          2m46s
pod/blog-86d5488fc4-h9tz5   0/1     Running   0          2m2s
$ kubectl get deployment blog -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Available=True MinimumReplicasAvailable
Progressing=False ProgressDeadlineExceeded
$ NEW=$(kubectl get pods -l app=blog -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==false)]}{.metadata.name}{end}'); echo $NEW
blog-86d5488fc4-h9tz5
$ kubectl describe pod $NEW | grep -E 'Image:|Port:|Readiness:|Warning'
    Image:          nginxinc/nginx-unprivileged:1.29.8-alpine
    Port:           80/TCP (http)
    Host Port:      0/TCP (http)
    Readiness:      http-get http://:http/ delay=0s timeout=1s period=2s successThreshold=1 failureThreshold=3
  Warning  Unhealthy  67s (x25 over 113s)  kubelet            spec.containers{blog}: Readiness probe failed: Get "http://10.244.1.13:80/": dial tcp 10.244.1.13:80: connect: connection refused
$ kubectl exec $NEW -- grep -m1 listen /etc/nginx/conf.d/default.conf
    listen       8080;
$ kubectl rollout history deployment blog
deployment.apps/blog 
REVISION  CHANGE-CAUSE
1         1.0: first release
2         1.1: run as non-root (nginx-unprivileged image)

$ kubectl rollout undo deployment blog
Warning: resource deployments/blog was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/blog rolled back
$ kubectl rollout status deployment blog
deployment "blog" successfully rolled out
$ kubectl get rs -l app=blog
NAME              DESIRED   CURRENT   READY   AGE
blog-7b9f956dc4   2         2         2       2m46s
blog-86d5488fc4   0         0         0       2m2s
$ kubectl rollout history deployment blog
deployment.apps/blog 
REVISION  CHANGE-CAUSE
2         1.1: run as non-root (nginx-unprivileged image)
3         1.0: first release

$ cd ~/allcsvideos
$ sed -i 's/containerPort: 80}/containerPort: 8080}/; s/"1.1: run as non-root (nginx-unprivileged image)"/"1.1.1: non-root image, listens on 8080"/' blog.yaml
$ kubectl diff -f blog.yaml | grep '^[-+] '
-    kubernetes.io/change-cause: '1.0: first release'
+    kubernetes.io/change-cause: '1.1.1: non-root image, listens on 8080'
-  generation: 3
+  generation: 4
-      - image: nginx:1.29.8-alpine
+      - image: nginxinc/nginx-unprivileged:1.29.8-alpine
-        - containerPort: 80
+        - containerPort: 8080
$ kubectl apply -f blog.yaml
deployment.apps/blog configured
$ kubectl rollout status deployment blog
Waiting for deployment "blog" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "blog" rollout to finish: 1 old replicas are pending termination...
deployment "blog" successfully rolled out
$ kubectl rollout history deployment blog
deployment.apps/blog 
REVISION  CHANGE-CAUSE
2         1.1: run as non-root (nginx-unprivileged image)
3         1.0: first release
4         1.1.1: non-root image, listens on 8080
```

Your revision numbers may differ if you rolled out the blog more than once. Notice that `undo` doesn't create the old revision again: revision 1 became revision 3.

**Why it works:** version 1.1 switched to the `nginx-unprivileged` image, which runs as a normal user and therefore listens on **8080**, not 80. The readiness probe kept asking port 80: connection refused, never ready. With `maxUnavailable: 0`, no old pod was touched, so the blog kept serving from version 1.0 the whole time, and after 60 seconds without progress (`progressDeadlineSeconds: 60`) the Deployment marked itself `ProgressDeadlineExceeded`, and `rollout status` exits with 1, which stops a pipeline. `undo` brought back revision 1's template as a new revision. Because `undo` doesn't update the file (kubectl warns about exactly that), the real fix went into `blog.yaml`: port 8080 and an honest change-cause, applied and rolled out cleanly.

</details>

---

### L05 · Services and DNS

### 17 · A Service that selects nothing (L05)

The catalog pods run, but calling the Service fails. Find out why, from the Service's point of view, and fix `catalog.yaml`. Use the Copilot pod as your client: it has busybox's `wget`.

<details>
<summary>Hint</summary>

Empty endpoints almost always mean a label mismatch, or no ready pods. Compare the `Selector` in `kubectl describe service` with `kubectl get pods --show-labels`, and look at the EndpointSlice (`-l kubernetes.io/service-name=catalog`).

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl exec deploy/copilot -- wget -qO- -T 3 http://catalog:8080/courses.json
wget: can't connect to remote host (10.96.119.83): Connection refused
command terminated with exit code 1
$ kubectl get endpointslices -l kubernetes.io/service-name=catalog
NAME            ADDRESSTYPE   PORTS     ENDPOINTS   AGE
catalog-n9wg5   IPv4          <unset>   <unset>     2m51s
$ kubectl describe service catalog | grep -E 'Selector|Endpoints'
Selector:                 app=catalog,tier=api
Endpoints:                
$ kubectl get pods -l app=catalog --show-labels
NAME                     READY   STATUS    RESTARTS   AGE   LABELS
catalog-c8d6c688-cgdcv   1/1     Running   0          11s   app=catalog,pod-template-hash=c8d6c688,tier=backend
catalog-c8d6c688-cvk69   1/1     Running   0          5s    app=catalog,pod-template-hash=c8d6c688,tier=backend
catalog-c8d6c688-zxb7v   1/1     Running   0          12s   app=catalog,pod-template-hash=c8d6c688,tier=backend
$ kubectl get pods -l app=catalog,tier=api
No resources found in allcsvideos namespace.
$ cd ~/allcsvideos
$ sed -i 's/selector: {app: catalog, tier: api}/selector: {app: catalog}/' catalog.yaml
$ kubectl apply -f catalog.yaml
configmap/catalog-settings unchanged
configmap/catalog-data unchanged
deployment.apps/catalog unchanged
service/catalog configured
$ kubectl get endpointslices -l kubernetes.io/service-name=catalog
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
catalog-n9wg5   IPv4          8080    10.244.1.21,10.244.1.19,10.244.1.22   2m51s
$ kubectl exec deploy/copilot -- wget -qO- -T 3 http://catalog:8080/courses.json
[
  {"id": "dsa", "title": "Data Structures and Algorithms"},
  {"id": "devops", "title": "DevOps: From Linux to Kubernetes in Production"}
]
```

Your pod IPs differ.

**Why it works:** the Service selected `app=catalog,tier=api`, but the pods are `tier=backend`. A pod must match **every** label in a selector, so no pod matched, the EndpointSlice stayed empty, and kube-proxy installed a reject rule for the Service: connection refused, at once. Selecting on `app: catalog` alone matches all three pods, and the EndpointSlice controller filled the slice right away.

</details>

### 18 · How a name becomes an address (L05) · Investigate

From the Copilot pod, find out which DNS server the pod uses and which search domains it tries, and resolve the catalog Service by its full name. Then show from the staging namespace (the staging storefront, an nginx Alpine image with busybox tools) that the short name `catalog` fails there and `catalog.allcsvideos` works. Explain both.

<details>
<summary>Hint</summary>

The kubelet writes every pod's `/etc/resolv.conf`. The full name of a Service is `<service>.<namespace>.svc.cluster.local`. busybox's `nslookup` prints a line for every search domain it tries, so give it the full name; `wget` uses the search list like a normal app.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl exec deploy/copilot -- cat /etc/resolv.conf
search allcsvideos.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
$ kubectl get service kube-dns -n kube-system
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   3m15s
$ kubectl exec deploy/copilot -- nslookup catalog.allcsvideos.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	catalog.allcsvideos.svc.cluster.local
Address: 10.96.119.83


$ kubectl get service catalog
NAME      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
catalog   ClusterIP   10.96.119.83   <none>        8080/TCP   2m52s
$ kubectl -n allcsvideos-staging exec deploy/storefront -- cat /etc/resolv.conf
search allcsvideos-staging.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
$ kubectl -n allcsvideos-staging exec deploy/storefront -- wget -qO- -T 3 http://catalog:8080/courses.json
wget: bad address 'catalog:8080'
command terminated with exit code 1
$ kubectl -n allcsvideos-staging exec deploy/storefront -- wget -qO- -T 3 http://catalog.allcsvideos:8080/courses.json
[
  {"id": "dsa", "title": "Data Structures and Algorithms"},
  {"id": "devops", "title": "DevOps: From Linux to Kubernetes in Production"}
]
```

**Why it works:** every pod's `resolv.conf` points at `10.96.0.10`, the `kube-dns` Service in front of CoreDNS, and CoreDNS answers `catalog.allcsvideos.svc.cluster.local` with the Service's cluster IP, the same one `get service` shows. The search list starts with the pod's **own** namespace. In `allcsvideos`, `catalog` becomes `catalog.allcsvideos.svc.cluster.local`. In `allcsvideos-staging` it becomes `catalog.allcsvideos-staging.svc.cluster.local`, which doesn't exist. `catalog.allcsvideos` plus the second search domain, `svc.cluster.local`, works from anywhere. Short name inside a namespace, add the namespace from outside it.

</details>

### 19 · A headless Service (L05)

The team wants a name that returns the individual catalog pods, not one virtual IP. Create a headless Service `catalog-headless` as a file in the repository, and show what DNS returns for it.

<details>
<summary>Hint</summary>

A headless Service sets `clusterIP: None`. `kubectl expose` takes `--cluster-ip=None`. Compare the answer of `nslookup` with `kubectl get pods -o wide`.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/allcsvideos
$ kubectl expose deployment catalog --name=catalog-headless --cluster-ip=None --port=8080 --dry-run=client -o yaml > catalog-headless.yaml
$ grep -A8 '^spec:' catalog-headless.yaml
spec:
  clusterIP: None
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app: catalog
status:
$ kubectl apply -f catalog-headless.yaml
service/catalog-headless created
$ kubectl get services catalog catalog-headless
NAME               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
catalog            ClusterIP   10.96.119.83   <none>        8080/TCP   2m53s
catalog-headless   ClusterIP   None           <none>        8080/TCP   0s
$ kubectl exec deploy/copilot -- nslookup catalog-headless.allcsvideos.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	catalog-headless.allcsvideos.svc.cluster.local
Address: 10.244.1.19
Name:	catalog-headless.allcsvideos.svc.cluster.local
Address: 10.244.1.22
Name:	catalog-headless.allcsvideos.svc.cluster.local
Address: 10.244.1.21


$ kubectl get pods -l app=catalog -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP            NODE              NOMINATED NODE   READINESS GATES
catalog-c8d6c688-cgdcv   1/1     Running   0          13s   10.244.1.21   m13lab-worker     <none>           <none>
catalog-c8d6c688-cvk69   1/1     Running   0          7s    10.244.1.22   m13lab-worker     <none>           <none>
catalog-c8d6c688-zxb7v   1/1     Running   0          14s   10.244.1.19   m13lab-worker     <none>           <none>
```

**Why it works:** with no cluster IP there's nothing for kube-proxy to program, so CoreDNS answers with the ready pods' own IPs, one record per pod, the same three as `get pods -o wide`. The client picks one. Use it when clients must reach a specific pod, like database replicas, or balance by themselves. Module 14's StatefulSets build on this.

</details>

---

### L06 · ConfigMaps and Secrets

### 20 · CrashLoopBackOff from a missing key (L06)

The email worker crashes at start. Find out what it's missing, fix `worker.yaml`, and get it running now, not in five minutes.

<details>
<summary>Hint</summary>

`kubectl logs` shows the output of the crashed run. The worker reads its settings from the ConfigMap `worker-config` with `envFrom`: every key becomes a variable with the same name. Environment variables are read when a container starts, and a crash-looping pod waits up to five minutes between tries. `kubectl rollout restart` makes new pods now.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl get pods -l app=worker
NAME                      READY   STATUS   RESTARTS      AGE
worker-5846c67d66-mkzd8   0/1     Error    4 (97s ago)   2m55s
$ kubectl logs deploy/worker
worker: QUEUE_URL is not set, cannot start
$ kubectl get configmap worker-config -o jsonpath='{.data}{"\n"}'
{"QUEUE_NAME":"emails","QUEUE_ULR":"redis://queue:6379/0"}
$ cd ~/allcsvideos
$ sed -i 's/QUEUE_ULR:/QUEUE_URL:/' worker.yaml
$ kubectl apply -f worker.yaml
configmap/worker-config configured
deployment.apps/worker unchanged
$ kubectl rollout restart deployment worker
deployment.apps/worker restarted
$ kubectl rollout status deployment worker
Waiting for deployment "worker" rollout to finish: 1 old replicas are pending termination...
deployment "worker" successfully rolled out
$ kubectl get pods -l app=worker
NAME                      READY   STATUS        RESTARTS      AGE
worker-5846c67d66-mkzd8   0/1     Terminating   4 (98s ago)   2m56s
worker-77cdd584b7-pbchd   1/1     Running       0             1s
$ kubectl logs deploy/worker
Found 2 pods, using pod/worker-77cdd584b7-pbchd
worker: consuming queue emails from redis://queue:6379/0
```

**Why it works:** the key was spelt `QUEUE_ULR`, so `envFrom` created a variable `QUEUE_ULR` and the app found no `QUEUE_URL`. Fixing the ConfigMap doesn't touch a container that is already running: the kubelet builds the environment when it creates a container. A crash-looping pod would pick the new key up at its next try, but the back-off between tries grows to five minutes. `rollout restart` stamps a `restartedAt` annotation into the pod template, so new pods start right away, and they read the fixed ConfigMap.

</details>

### 21 · The Secret key that wasn't there (L06)

The mailer has said `ContainerCreating` since last night. Find out why, fix `mailer.yaml` without changing the Secret, and check where the password file lives in the running pod.

<details>
<summary>Hint</summary>

The events at the bottom of `describe pod` say which volume can't be mounted. `kubectl describe secret` lists a Secret's keys and their sizes, never the values. A Secret volume with `items` must name keys that exist.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl get pods -l app=mailer
NAME                     READY   STATUS              RESTARTS   AGE
mailer-9c66dc4d6-j4s4k   0/1     ContainerCreating   0          2m56s
$ kubectl describe pod -l app=mailer | sed -n '/^Events:/,$p' | tail -2
  Normal   Scheduled         2m55s                default-scheduler  Successfully assigned allcsvideos/mailer-9c66dc4d6-j4s4k to m13lab-worker
  Warning  FailedMount       46s (x9 over 2m54s)  kubelet            MountVolume.SetUp failed for volume "smtp" : references non-existent secret key: smtp-password
$ kubectl describe secret mail-creds | sed -n '/^Data/,$p'
Data
====
password:  22 bytes
username:  18 bytes
$ cd ~/allcsvideos
$ grep -n -B1 -A2 'items:' mailer.yaml
36-          secretName: mail-creds
37:          items:
38-          - {key: smtp-password, path: smtp-password}
$ sed -i 's/- {key: smtp-password, path: smtp-password}/- {key: password, path: smtp-password}/' mailer.yaml
$ kubectl apply -f mailer.yaml
secret/mail-creds configured
deployment.apps/mailer configured
$ kubectl rollout status deployment mailer
Waiting for deployment "mailer" rollout to finish: 1 old replicas are pending termination...
deployment "mailer" successfully rolled out
$ kubectl logs deploy/mailer
Found 2 pods, using pod/mailer-55b4d8489f-wwb9z
mailer: SMTP user mailer@example.com, password read from /etc/mailer/smtp-password (22 bytes)
$ kubectl exec deploy/mailer -- ls -la /etc/mailer
total 4
drwxrwxrwt    3 root     root           100 Oct 21 04:25 .
drwxr-xr-x    1 root     root          4096 Oct 21 04:25 ..
drwxr-xr-x    2 root     root            60 Oct 21 04:25 ..2026_10_21_04_25_27.3057267107
lrwxrwxrwx    1 root     root            32 Oct 21 04:25 ..data -> ..2026_10_21_04_25_27.3057267107
lrwxrwxrwx    1 root     root            20 Oct 21 04:25 smtp-password -> ..data/smtp-password
$ kubectl exec deploy/mailer -- df -h /etc/mailer
Filesystem                Size      Used Available Use% Mounted on
tmpfs                     7.8G      4.0K      7.8G   0% /etc/mailer
```

**Why it works:** the volume asked for the key `smtp-password`, but the Secret's keys are `password` and `username`, so the kubelet refused to mount the volume, and a container can't start without its volumes. `items` maps a key to a file name: `key: password, path: smtp-password` keeps the file name the app expects. The file is a link into `..data`, the same swap mechanism as a ConfigMap, and the folder is `tmpfs`: in memory, never on the node's disk. (`secret/mail-creds configured` appears on every apply of this file: `stringData` never stays in the stored object, so apply always sends it again. The values didn't change.)

</details>

### 22 · File versus environment variable (L06) · Investigate

The catalog moves to the `ap-south-2` region, and a third course is added to `courses.json`. Change both in `catalog.yaml`, apply, and find out which change reaches the running pods on its own, how long it takes, and what you need for the other one.

<details>
<summary>Hint</summary>

`CATALOG_REGION` comes in through `envFrom`, `courses.json` as a file from a ConfigMap volume. Check every pod: `kubectl exec POD -- printenv CATALOG_REGION` and `kubectl exec POD -- grep -c '"id"' /www/courses.json`. A small `until` loop measures how long the file takes.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/allcsvideos
$ sed -i 's/CATALOG_REGION: ap-south-1/CATALOG_REGION: ap-south-2/' catalog.yaml
$ sed -i 's|      {"id": "devops", "title": "DevOps: From Linux to Kubernetes in Production"}|      {"id": "devops", "title": "DevOps: From Linux to Kubernetes in Production"},\n      {"id": "genai", "title": "Generative AI with Python"}|' catalog.yaml
$ kubectl diff -f catalog.yaml | grep '^[-+] '
-      {"id": "devops", "title": "DevOps: From Linux to Kubernetes in Production"}
+      {"id": "devops", "title": "DevOps: From Linux to Kubernetes in Production"},
+      {"id": "genai", "title": "Generative AI with Python"}
-  CATALOG_REGION: ap-south-1
+  CATALOG_REGION: ap-south-2
$ kubectl apply -f catalog.yaml; date +%T
configmap/catalog-settings configured
configmap/catalog-data configured
deployment.apps/catalog unchanged
service/catalog unchanged
04:25:28
$ kubectl exec deploy/copilot -- wget -qO- http://catalog:8080/courses.json | grep -c '"id"'
2
$ start=$(date +%s); until [ "$(for p in $(kubectl get pods -l app=catalog -o name); do kubectl exec $p -- grep -c '"id"' /www/courses.json; done | sort -u)" = 3 ]; do sleep 2; done; echo "all catalog pods updated after $(( $(date +%s) - start )) s"; date +%T
all catalog pods updated after 78 s
04:26:46
$ for p in $(kubectl get pods -l app=catalog -o name); do echo "$p: $(kubectl exec $p -- grep -c '"id"' /www/courses.json) courses, $(kubectl exec $p -- printenv CATALOG_REGION)"; done
pod/catalog-c8d6c688-cgdcv: 3 courses, ap-south-1
pod/catalog-c8d6c688-cvk69: 3 courses, ap-south-1
pod/catalog-c8d6c688-zxb7v: 3 courses, ap-south-1
$ OLD=$(kubectl get rs -l app=catalog --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.labels.pod-template-hash}'); echo $OLD
c8d6c688
$ kubectl rollout restart deployment catalog
deployment.apps/catalog restarted
$ kubectl rollout status deployment catalog
Waiting for deployment "catalog" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "catalog" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "catalog" rollout to finish: 1 old replicas are pending termination...
deployment "catalog" successfully rolled out
$ kubectl wait --for=delete pod -l pod-template-hash=$OLD --timeout=60s
pod/catalog-c8d6c688-cvk69 condition met
$ for p in $(kubectl get pods -l app=catalog -o name); do echo "$p: $(kubectl exec $p -- printenv CATALOG_REGION)"; done
pod/catalog-5b69fff9b7-5bqbm: ap-south-2
pod/catalog-5b69fff9b7-92t5n: ap-south-2
pod/catalog-5b69fff9b7-gpgq2: ap-south-2
```

Your time will differ: anything up to about a minute and a half is normal, and each pod gets the new file at its own moment.

**Why it works:** a ConfigMap volume is updated by each pod's kubelet on its next sync (lesson 6 measured 53 to 82 seconds), and busybox `httpd` reads the file again on every request, so the new course appeared with no restart. The environment variable was copied in once, when each container started, and never changes in a running container. For env vars, `subPath` mounts and apps that read their config only at start, a ConfigMap change needs new pods: `rollout restart`.

</details>

---

## Final challenge

Three tasks that each combine several lessons. They need the fixes from tasks 13, 15 and 17: do those first.

### 23 · The storefront, end to end (L04, L05, L06)

Make `http://127.0.0.1:30080/` and `http://127.0.0.1:30080/api/courses.json` both answer, from the tool box and from your own machine's browser. Find every problem on the way, fix them in `storefront.yaml`, and record the change in the rollout history.

<details>
<summary>Hint</summary>

Follow the request: NodePort 30080, the Service, its EndpointSlice and the port it sends to, the container's real port. Then the second hop: nginx proxies `/api/` to the catalog, so read nginx's `error.log` (it's in the pod, at `/var/log/nginx`), its config in the ConfigMap `storefront-nginx`, and the catalog Service's port. Remember when nginx reads its config.

</details>

<details>
<summary>Answer</summary>

```text
$ curl -sS --max-time 5 http://127.0.0.1:30080/
curl: (7) Failed to connect to 127.0.0.1:30080 after 3 ms: Could not connect to server
$ kubectl get service storefront
NAME         TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
storefront   NodePort   10.96.235.50   <none>        80:30080/TCP   4m18s
$ kubectl get endpointslices -l kubernetes.io/service-name=storefront
NAME               ADDRESSTYPE   PORTS   ENDPOINTS               AGE
storefront-wrkkk   IPv4          8080    10.244.1.9,10.244.1.8   4m18s
$ kubectl get pods -l app=storefront -o jsonpath='{.items[0].spec.containers[0].ports}{"\n"}'
[{"containerPort":80,"name":"http","protocol":"TCP"}]
$ cd ~/allcsvideos
$ sed -i 's/    targetPort: 8080/    targetPort: http/' storefront.yaml
$ kubectl apply -f storefront.yaml
configmap/storefront-html unchanged
configmap/storefront-nginx unchanged
deployment.apps/storefront unchanged
service/storefront configured
$ kubectl get endpointslices -l kubernetes.io/service-name=storefront
NAME               ADDRESSTYPE   PORTS   ENDPOINTS               AGE
storefront-wrkkk   IPv4          80      10.244.1.9,10.244.1.8   4m19s
$ curl -sS --retry 5 --retry-connrefused --retry-delay 1 --max-time 5 http://127.0.0.1:30080/
curl: (7) Failed to connect to 127.0.0.1:30080 after 0 ms: Could not connect to server
<!doctype html>
<title>allcsvideos</title>
<h1>allcsvideos storefront</h1>
<p>version 1.0</p>
$ curl -sS --max-time 10 -o /dev/null -w 'HTTP %{http_code} after %{time_total} s\n' http://127.0.0.1:30080/api/courses.json
HTTP 504 after 3.004168 s
$ for p in $(kubectl get pods -l app=storefront -o name); do kubectl exec $p -c web -- grep -h 'timed out' /var/log/nginx/error.log; done | tail -1
command terminated with exit code 1
2026/10/21 04:26:54 [error] 31#31: *113 upstream timed out (110: Operation timed out) while connecting to upstream, client: 172.18.0.3, server: , request: "GET /api/courses.json HTTP/1.1", upstream: "http://10.96.119.83:80/courses.json", host: "127.0.0.1:30080"
$ kubectl get configmap storefront-nginx -o jsonpath='{.data.default\.conf}' | grep proxy_pass
    proxy_pass http://catalog:80/;
$ kubectl get service catalog
NAME      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
catalog   ClusterIP   10.96.119.83   <none>        8080/TCP   4m23s
$ sed -i 's|proxy_pass http://catalog:80/;|proxy_pass http://catalog:8080/;|' storefront.yaml
$ kubectl apply -f storefront.yaml; date +%T
configmap/storefront-html unchanged
configmap/storefront-nginx configured
deployment.apps/storefront unchanged
service/storefront unchanged
04:26:54
$ until [ "$(for p in $(kubectl get pods -l app=storefront -o name); do kubectl exec $p -c web -- cat /etc/nginx/conf.d/default.conf | grep -c 'catalog:8080'; done | sort -u)" = 1 ]; do sleep 2; done; date +%T
04:27:16
$ curl -sS --max-time 10 -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:30080/api/courses.json
HTTP 504
$ kubectl rollout restart deployment storefront
deployment.apps/storefront restarted
$ kubectl annotate deployment storefront kubernetes.io/change-cause="1.0.1: catalog API on port 8080" --overwrite
deployment.apps/storefront annotated
$ sed -i 's/change-cause: ".*"/change-cause: "1.0.1: catalog API on port 8080"/' storefront.yaml
$ kubectl rollout status deployment storefront
Waiting for deployment "storefront" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "storefront" rollout to finish: 1 old replicas are pending termination...
deployment "storefront" successfully rolled out
$ curl -sS --retry 5 --retry-connrefused --retry-delay 1 --max-time 5 -w 'HTTP %{http_code}\n' http://127.0.0.1:30080/api/courses.json
[
  {"id": "dsa", "title": "Data Structures and Algorithms"},
  {"id": "devops", "title": "DevOps: From Linux to Kubernetes in Production"},
  {"id": "genai", "title": "Generative AI with Python"}
]
HTTP 200
$ kubectl rollout history deployment storefront
deployment.apps/storefront 
REVISION  CHANGE-CAUSE
1         1.0: first release on Kubernetes
2         1.0.1: catalog API on port 8080

$ kubectl diff -f storefront.yaml; echo "exit code: $?"
exit code: 0
```

Your cluster IPs and timings differ. The first `curl` after the Service fix may print one `Failed to connect` before the page, as here: kube-proxy needs a moment to rewrite the node's rules, and `--retry-connrefused` simply tries again. Port 30080 is published on your own machine too, so the same two `curl` commands work in your machine's terminal, and the two URLs open in your browser.

**Why it works:** two separate bugs. First, the Service sent traffic to `targetPort: 8080`, but nginx listens on 80: the EndpointSlice listed the pods on port 8080, and every connection was refused. `targetPort: http` follows the container's named port and can't drift again. Second, nginx proxied to `catalog:80`, but the catalog Service only has port 8080: nothing answers on port 80 of the cluster IP, and after `proxy_connect_timeout` (3 s) nginx returned 504. The fixed ConfigMap reached the pods' files within a minute (22 seconds here), but nginx still answered 504: nginx reads its config once, at start. `rollout restart` made new pods that read it. The change-cause was set after the restart, so it lands on the new revision.

</details>

### 24 · Ship storefront 2.0 safely, then roll back (L03, L04, L05, L06)

The new home page is ready in `storefront-html-v2.yaml`. Measure with real traffic how many requests a storefront rollout drops, and fix what makes it drop them. Then ship 2.0 as a declarative change with its own change-cause, roll back to 1.0 under traffic, and leave the repository matching the cluster.

<details>
<summary>Hint</summary>

Check the strategy and the readiness probe first. Then rehearse: a small `traffic` function that curls the NodePort in a loop for 25 seconds while you run `kubectl rollout restart`, and counts versions and failures. nginx stops at once on SIGTERM, but the endpoint removal takes a moment to reach every node: lesson 3's `preStop` hook can keep the old pod serving a few seconds longer. 2.0 means pointing the `html` volume at the ConfigMap `storefront-html-v2`: a new name changes the template, so it rolls out.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl get deployment storefront -o jsonpath='{.spec.strategy.rollingUpdate}{"\n"}{.spec.template.spec.containers[0].readinessProbe.httpGet}{"\n"}'
{"maxSurge":1,"maxUnavailable":0}
{"path":"/healthz","port":"http","scheme":"HTTP"}
$ traffic(){ end=$(( $(date +%s) + $1 )); while [ $(date +%s) -lt $end ]; do curl -s --max-time 2 http://127.0.0.1:30080/ | grep -o 'version [0-9.]*' || echo FAILED; sleep 0.05; done > /tmp/traffic.txt; }
$ traffic 25 & sleep 3; kubectl rollout restart deployment storefront; kubectl rollout status deployment storefront; wait
deployment.apps/storefront restarted
Waiting for deployment "storefront" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "storefront" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "storefront" rollout to finish: 1 old replicas are pending termination...
deployment "storefront" successfully rolled out
$ sort /tmp/traffic.txt | uniq -c
      3 FAILED
    383 version 1.0
$ cd ~/allcsvideos
$ sed -i 's|^        readinessProbe:|        lifecycle:\n          preStop:\n            exec: {command: ["sleep", "5"]}\n        readinessProbe:|; s/change-cause: ".*"/change-cause: "1.0.2: wait 5 s before nginx stops"/' storefront.yaml
$ sed -n '/- name: web/,/readinessProbe:/p' storefront.yaml
      - name: web
        image: nginx:1.29.8-alpine
        ports: [{name: http, containerPort: 80}]
        lifecycle:
          preStop:
            exec: {command: ["sleep", "5"]}
        readinessProbe:
$ kubectl apply -f storefront.yaml
configmap/storefront-html unchanged
configmap/storefront-nginx unchanged
deployment.apps/storefront configured
service/storefront unchanged
$ kubectl rollout status deployment storefront
Waiting for deployment "storefront" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "storefront" rollout to finish: 1 old replicas are pending termination...
deployment "storefront" successfully rolled out
$ kubectl apply -f storefront-html-v2.yaml
configmap/storefront-html-v2 created
$ sed -i 's/{name: html, configMap: {name: storefront-html}}/{name: html, configMap: {name: storefront-html-v2}}/; s/change-cause: ".*"/change-cause: "2.0: new home page"/' storefront.yaml
$ kubectl diff -f storefront.yaml | grep '^[-+] '
-    kubernetes.io/change-cause: '1.0.2: wait 5 s before nginx stops'
+    kubernetes.io/change-cause: '2.0: new home page'
-  generation: 7
+  generation: 8
-          name: storefront-html
+          name: storefront-html-v2
$ traffic 25 & sleep 3; kubectl apply -f storefront.yaml; kubectl rollout status deployment storefront; wait
configmap/storefront-html unchanged
configmap/storefront-nginx unchanged
deployment.apps/storefront configured
service/storefront unchanged
Waiting for deployment "storefront" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "storefront" rollout to finish: 1 old replicas are pending termination...
deployment "storefront" successfully rolled out
$ sort /tmp/traffic.txt | uniq -c
      1 FAILED
     59 version 1.0
    334 version 2.0
$ curl -s http://127.0.0.1:30080/
<!doctype html>
<title>allcsvideos</title>
<h1>allcsvideos storefront</h1>
<p>version 2.0: new home page with course search</p>
$ kubectl rollout history deployment storefront
deployment.apps/storefront 
REVISION  CHANGE-CAUSE
1         1.0: first release on Kubernetes
2         1.0.1: catalog API on port 8080
3         1.0.1: catalog API on port 8080
4         1.0.2: wait 5 s before nginx stops
5         2.0: new home page

$ traffic 25 & sleep 3; kubectl rollout undo deployment storefront; kubectl rollout status deployment storefront; wait
Warning: resource deployments/storefront was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/storefront rolled back
Waiting for deployment "storefront" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "storefront" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "storefront" rollout to finish: 1 old replicas are pending termination...
deployment "storefront" successfully rolled out
$ sort /tmp/traffic.txt | uniq -c
    338 version 1.0
     97 version 2.0
$ curl -s http://127.0.0.1:30080/
<!doctype html>
<title>allcsvideos</title>
<h1>allcsvideos storefront</h1>
<p>version 1.0</p>
$ kubectl rollout history deployment storefront
deployment.apps/storefront 
REVISION  CHANGE-CAUSE
1         1.0: first release on Kubernetes
2         1.0.1: catalog API on port 8080
3         1.0.1: catalog API on port 8080
5         2.0: new home page
6         1.0.2: wait 5 s before nginx stops

$ sed -i 's/{name: html, configMap: {name: storefront-html-v2}}/{name: html, configMap: {name: storefront-html}}/; s/change-cause: ".*"/change-cause: "1.0.2: wait 5 s before nginx stops"/' storefront.yaml
$ kubectl apply -f storefront.yaml
configmap/storefront-html unchanged
configmap/storefront-nginx unchanged
deployment.apps/storefront configured
service/storefront unchanged
$ kubectl diff -f storefront.yaml; echo "exit code: $?"
exit code: 0
```

Your request counts differ with your machine's speed, and so may the number of failures. In your interactive shell, bash also prints the job lines `[1] 12345` and `[1]+  Done` around each `traffic` run.

**Why it works:** the strategy (surge 1, unavailable 0) and the readiness probe were already right: new pods got traffic only when ready, and capacity never dropped. The failures came from the **old** pods: as soon as a pod is Terminating, nginx gets SIGTERM and stops at once, while kube-proxy on the node is still removing it from its rules. Requests in that gap were refused. The `preStop` hook runs first and keeps nginx serving for 5 seconds while the endpoint disappears everywhere, and only then does SIGTERM arrive. With it, the 2.0 rollout lost 1 request of 394 here and the rollback none. We repeated the rollout 11 more times with the hook: 0 failures every time, while every run without it lost 3 to 11. So the hook closes almost the whole gap, but a NodePort and kube-proxy can't promise zero: production puts a proxy with retries in front (Ingress, module 14). Note also that `rollout restart` copied the current change-cause into revision 3: set the change-cause after a restart, as in task 23. `undo` brings back revision 2's template as a new revision, and putting the old name back in the file makes git match the cluster: `apply` changes nothing in the template, so no extra rollout.

</details>

### 25 · Prove the Secret is not encrypted (L06) · Investigate

The chat says the email password is "encrypted in a Secret". Prove, with only the cluster and the repository, every place where `demo-smtp-password-123` can be read in plain text, and say whether this cluster encrypts Secrets at rest.

<details>
<summary>Hint</summary>

`kubectl get secret -o jsonpath='{.data.password}'` and `base64 -d`. Look at the `last-applied-configuration` annotation that `kubectl apply` left on the Secret. Read the mounted file. Check the kube-apiserver pod for `--encryption-provider-config`. And, read-only, in your own lab: lesson 6's `etcdctl get` inside the etcd pod, with the node's certificates.

</details>

<details>
<summary>Answer</summary>

```text
$ kubectl describe secret mail-creds | sed -n '/^Data/,$p'
Data
====
password:  22 bytes
username:  18 bytes
$ kubectl get secret mail-creds -o jsonpath='{.data.password}'; echo
ZGVtby1zbXRwLXBhc3N3b3JkLTEyMw==
$ kubectl get secret mail-creds -o jsonpath='{.data.password}' | base64 -d; echo
demo-smtp-password-123
$ echo -n 'demo-smtp-password-123' | base64
ZGVtby1zbXRwLXBhc3N3b3JkLTEyMw==
$ kubectl get secret mail-creds -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' | jq .stringData
{
  "password": "demo-smtp-password-123",
  "username": "mailer@example.com"
}
$ kubectl exec deploy/mailer -- cat /etc/mailer/smtp-password; echo
demo-smtp-password-123
$ grep -n -A3 '^stringData' ~/allcsvideos/mailer.yaml
8:stringData:
9-  username: mailer@example.com
10-  password: demo-smtp-password-123
11----
$ kubectl -n kube-system get pod kube-apiserver-m13lab-control-plane -o yaml | grep -c encryption-provider-config
0
$ E='--cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key'
$ kubectl -n kube-system exec etcd-m13lab-control-plane -- etcdctl $E get /registry/secrets/allcsvideos/mail-creds | hexdump -C | tail -6
000002d0  61 73 73 77 6f 72 64 12  16 64 65 6d 6f 2d 73 6d  |assword..demo-sm|
000002e0  74 70 2d 70 61 73 73 77  6f 72 64 2d 31 32 33 12  |tp-password-123.|
000002f0  1e 0a 08 75 73 65 72 6e  61 6d 65 12 12 6d 61 69  |...username..mai|
00000300  6c 65 72 40 65 78 61 6d  70 6c 65 2e 63 6f 6d 1a  |ler@example.com.|
00000310  06 4f 70 61 71 75 65 1a  00 22 00 0a              |.Opaque.."..|
0000031c
$ kubectl -n kube-system exec etcd-m13lab-control-plane -- etcdctl $E get /registry/secrets/allcsvideos/mail-creds | strings | grep demo-smtp
{"apiVersion":"v1","kind":"Secret","metadata":{"annotations":{},"labels":{"app":"mailer"},"name":"mail-creds","namespace":"allcsvideos"},"stringData":{"password":"demo-smtp-password-123","username":"mailer@example.com"},"type":"Opaque"}
demo-smtp-password-123
```

**What it proves:** `describe` hides the value, but that's politeness, not protection. In the API the password is base64, an encoding anyone reverses with one command, with no key. `kubectl apply` stored the whole file, `stringData` included, in plain text in the `last-applied-configuration` annotation (lesson 6: `apply --server-side` doesn't write it). Any pod that mounts the Secret reads it in clear. The repository itself has it in plain text, which is why Secret YAML never belongs in git. And the API server runs without `--encryption-provider-config`, so etcd stores the Secret as plain bytes, **twice** here (the data and the annotation), and every etcd backup has them too. To protect it: encryption at rest (KMS v2, or `secretbox` in a lab, then rewrite the old Secrets), RBAC on `get`, `list`, `watch` and on creating pods, and the real value in a secret manager, never in git (lesson 6, and module 18).

</details>

---

## Clean up

When you're done, delete the cluster and the tool box. Inside the tool box:

```bash
lab-down
```

Then on your machine:

```bash
docker rm -f m13lab-tools
docker rmi m13lab-tools
```

The pulled images can stay: `kindest/node:v1.37.0`, `docker:29.5.3-cli`, and inside the nodes, which were deleted with them, `busybox:1.37.0`, `nginx:1.29.8-alpine`, `nginxinc/nginx-unprivileged:1.29.8-alpine` and `postgres:18.6-alpine3.24`. **Don't** delete the Docker network called `kind`: kind shares it between all clusters, and other labs may still use it.

These should all print nothing (apart from the header line of `docker ps`):

```bash
docker ps -a --filter name=m13lab
docker images --filter reference='m13lab*' -q
docker network ls --filter name=m13lab -q
docker volume ls --filter name=m13lab -q
```

**Score yourself:** 19 to 22 of the regular tasks solved on your own, plus at least one from the final challenge, means you're ready for Module 14. Under 15, rewatch the lessons named in the titles of the tasks you missed. Notice the order every fix followed: **context, events, labels, ports, then config**. Which cluster am I on? What do the events and the container state say? Do the selectors match the labels? Do the ports line up, from the Service to the container? Is the config the pod read the config you think it read? Those five questions find almost every broken Kubernetes app.
