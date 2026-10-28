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
