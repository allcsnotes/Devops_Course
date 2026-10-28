# M21-L04 · Full Mock Interview
> Video: Module 21, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- How a full technical loop feels: Linux and networking, Docker and Kubernetes, then CI/CD and cloud design
- How to give a good "I don't know": what you're sure of, how you'd check, then check
- How to recover from a weak first answer by measuring instead of guessing
- How to start a design with requirements and an estimate, then the path of one change
- How to score yourself with an example four-area rubric, and a checklist for the real interview

## Before you start
- Docker Desktop, kind v0.33.0 and kubectl v1.37.1 (the node image is pinned to `kindest/node:v1.37.0` by digest)
- The course's `allcsvideos` folder (round 2 copies Course Copilot from `../../allcsvideos/copilot`)
- Lessons to revisit if a round feels hard: [M02-L03](../../linux/m02-l03-processes-signals-and-systemd/),
  [M04-L05](../../networking/m04-l05-the-troubleshooting-toolbox/), [M07-L01](../../docker/m07-l01-small-fast-images/),
  [M13-L05](../../k8s/m13-l05-services-and-dns/), [M20-L01](../../capstones/m20-l01-designing-a-production-delivery-platform/)

Pause at every question and answer it out loud before you run anything. That is the point of a mock.
Everything runs locally and costs nothing. The faults are staged on purpose.

## Files in this folder
| File | What it is |
|---|---|
| `web01/Dockerfile` | Round 1 server: Ubuntu 24.04 with systemd as PID 1, nginx 1.24, users asha and priya, a lab CA and an HTTPS site for `shop.allcs.test` (lab-only keys, made at build time) |
| `web01/old-preview.service` | Priya's leftover preview server (`python3 -m http.server 80`), enabled at boot |
| `web01/shop.conf` | nginx HTTPS server block for `shop.allcs.test` |
| `web01/up.sh`, `web01/down.sh` | Start web-01 with the staged fault (nginx stopped, preview holding port 80) / remove it |
| `copilot/before/Dockerfile` | The team's first Copilot Dockerfile (compilers, `COPY . .` before pip, dev requirements, root, shell form) |
| `copilot/after/Dockerfile`, `.dockerignore` | Asha's version: two stages, venv, non-root user 10001, exec form |
| `copilot/setup.sh` | Copies Copilot from `allcsvideos/copilot` into `~/copilot-mock/before` and `~/copilot-mock/after` with the two Dockerfiles |
| `k8s/kind-cluster.yaml`, `k8s/catalog.yaml` | One-node kind cluster; catalog Deployment (port 8080, named `http`) and a Service with a staged wrong `targetPort: 80` |
| `k8s/up.sh` | Creates the kind cluster `mock`, applies `catalog.yaml`, starts a `client` pod (`curlimages/curl:8.17.0`) |

## The example rubric
Each round is scored 1-4 on four areas (written for this course; real companies write their own):
**Method** (a clear, safe order of steps), **Correctness** (are the facts right?), **Evidence** (a command, output or
number behind each claim), **Communication** (direct answer first, thinking out loud). A 4 is right, explained and
backed by evidence; a 2 is partly right, or a guess.

## Follow along

### Round 1: Linux and networking

1. Start web-01 and open a shell as asha:
   ```bash
   cd interview/m21-l04-full-mock-interview
   ./web01/up.sh
   docker exec -it -u asha -w /home/asha web-01 bash
   ```

2. **"Load average of five and a half. Is that bad?"** Measure before answering:
   ```bash
   nproc
   uptime
   ```
   ```
   10
    03:28:27 up 1 day,  3:54,  0 user,  load average: 5.54, 6.93, 7.47
   ```
   Your numbers will be your laptop's. Load only means something next to the core count; on Linux it also counts tasks
   waiting on disk, so a high load with idle CPUs points at storage (check `vmstat` next).

3. **"`> file 2>&1` versus `2>&1 > file`?"** Redirects apply left to right:
   ```bash
   ls /nope > a.log 2>&1; cat a.log
   ls /nope 2>&1 > b.log
   cat b.log; wc -c b.log
   ```
   The first log holds the error; the second prints the error on screen and `b.log` is 0 bytes.

4. **"Why can't Priya delete Asha's files in /tmp?"**
   ```bash
   ls -ld /tmp
   ```
   `drwxrwxrwt`: the final `t` is the sticky bit - only the file's owner, the folder's owner or root may delete or rename.

5. **"What's the conntrack limit, and what happens when it fills?"** A good "I don't know": say what you know, then check:
   ```bash
   sysctl net.netfilter.nf_conntrack_max
   sysctl net.netfilter.nf_conntrack_count
   ```
   ```
   net.netfilter.nf_conntrack_max = 262144
   net.netfilter.nf_conntrack_count = 0
   ```
   When full, the kernel drops new connections and logs "table full, dropping packet". Graph count against limit and alert early.

6. **Hands-on: "Since last night's maintenance, nginx won't start."** Reproduce and read the real error:
   ```bash
   sudo systemctl start nginx
   systemctl status nginx
   sudo journalctl -u nginx -n 8 --no-hostname --no-pager
   ```
   ```
   Process: 430 ExecStartPre=/usr/sbin/nginx -t -q -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
   Process: 431 ExecStart=/usr/sbin/nginx -g daemon on; master_process on; (code=exited, status=1/FAILURE)
   nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
   nginx: [emerg] still could not bind()
   ```
   The config test passed; the start failed on the port.

7. Who holds port 80, which user, since when, and which unit? (Use the PID you see.)
   ```bash
   sudo ss -ltnp "sport = :80"
   ps -o user,pid,lstart,args -p <PID>
   systemctl status <PID> | head -5
   ```
   ```
   LISTEN 0 5 0.0.0.0:80 0.0.0.0:* users:(("python3",pid=135,fd=3))
   priya        135 Thu Oct 22 03:28:06 2026 /usr/bin/python3 -m http.server 80 --bind 0.0.0.0 --direct
   ● old-preview.service - Temporary preview server (Priya)
   ```
   Before stopping it, ask the owner. ("It's left over from last week. Remove it.")

8. Fix it so a reboot can't bring it back, then verify:
   ```bash
   sudo systemctl disable --now old-preview
   sudo systemctl start nginx && systemctl is-active nginx
   curl -sI http://localhost | head -2
   ```
   ```
   active
   HTTP/1.1 200 OK
   Server: nginx/1.24.0 (Ubuntu)
   ```

9. **"The health check to https://shop.allcs.test still fails. Find the layer."** Bottom up: name, connection, TLS, HTTP:
   ```bash
   curl -v --connect-timeout 5 https://shop.allcs.test
   getent hosts shop.allcs.test; echo "exit $?"
   dig +short shop.allcs.test; echo "exit $?"
   ```
   ```
   curl: (6) Could not resolve host: shop.allcs.test
   exit 2
   exit 0
   ```
   `dig` asks the DNS server directly and never reads `/etc/hosts`; `getent` follows the system lookup order, like your apps.

10. In this lab the name belongs in the hosts file. Add it and climb to the next layer:
    ```bash
    echo '127.0.0.1 shop.allcs.test' | sudo tee -a /etc/hosts
    getent hosts shop.allcs.test
    curl -v --connect-timeout 5 https://shop.allcs.test
    ```
    ```
    * Connected to shop.allcs.test (127.0.0.1) port 443
    * TLSv1.3 (OUT), TLS alert, unknown CA (560):
    curl: (60) SSL certificate problem: unable to get local issuer certificate
    ```

11. Trust the lab CA for this request:
    ```bash
    curl -sS --cacert lab-ca.crt https://shop.allcs.test
    ```
    ```
    allcsvideos storefront ok
    ```
    In production, never "just add `-k`" - that turns verification off. Install the internal CA on clients, or use a public
    certificate (Let's Encrypt, [M04-L04](../../networking/m04-l04-http-tls-and-certificates/)). Type `exit` to leave web-01.

**Rahul's feedback:** strong - measured first, reproduced before fixing, found the owner before stopping anything, clean
layer test. Gap - `curl localhost` doesn't prove users can reach it; after any fix, test the user's path (load balancer
target health, the public name from outside, the error rate). Example score: 4 / 4 / 4 / 3 = 15 of 16.

### Round 2: Docker and Kubernetes

12. **"What would you change in this Dockerfile?"** Set up the two copies and read the first one out loud:
    ```bash
    ./copilot/setup.sh
    cd ~/copilot-mock
    ls -A before after
    cat before/Dockerfile
    ```
    Spot four problems: `build-essential` compilers for a service that compiles nothing; `COPY . .` before `pip install`;
    dev requirements (pytest) shipped to production; no `USER`, so it runs as root.

13. **"The image is too big. How would you make it smaller?"** "Switch to Alpine" is a guess. Measure first:
    ```bash
    docker build -q -t copilot:before before/
    docker build -q -t copilot:after after/
    docker images copilot
    docker images python:3.13.16-slim
    docker history copilot:before --format '{{.Size}}\t{{.CreatedBy}}' | head -6
    ```
    ```
    copilot:after    6c99aecb8e77   242MB   52.5MB
    copilot:before   d8565cc630b1   753MB    188MB
    python:3.13.16-slim  cf50a4f6ac4f  204MB  45.5MB
    54.6MB	RUN /bin/sh -c pip install -r requirements.t…
    352MB	RUN /bin/sh -c apt-get update && apt-get ins…
    ```
    The base isn't the problem; the compilers are. Alpine uses musl, so packages without a musl wheel need exactly those compilers.

14. Check Asha's version: layers, user, and that it still works:
    ```bash
    docker history copilot:after --format '{{.Size}}\t{{.CreatedBy}}' | head -6
    docker run --rm copilot:after id
    docker run --rm copilot:before id
    docker run -d --rm --name copilot -p 127.0.0.1:8000:8000 copilot:after
    sleep 3; curl -s 127.0.0.1:8000/health; echo
    docker stop copilot
    ```
    ```
    31.5MB	COPY /opt/venv /opt/venv # buildkit
    uid=10001(copilot) gid=10001(copilot) groups=10001(copilot)
    uid=0(root) gid=0(root) groups=0(root)
    {"status":"ok","version":"dev","courses":5}
    ```

15. **"A developer changes one line of code. What rebuilds?"**
    ```bash
    echo '# fix a comment' | tee -a before/app/main.py after/app/main.py
    time docker build -q -t copilot:before before/
    time docker build -q -t copilot:after after/
    echo '# second fix' | tee -a before/app/main.py after/app/main.py
    docker build --progress=plain -t copilot:before before/ 2>&1 | grep -A1 -E '^#[0-9]+ \[[0-9]/'
    docker build --progress=plain -t copilot:after after/ 2>&1 | grep -A1 -E '^#[0-9]+ \[(build|stage-1) [0-9]/'
    ```
    Video (busy laptop): before 14.6 s, after 1.8 s. Before: apt `CACHED`, but `COPY . .` and pip ran again. After:
    venv, requirements and `pip install` all `CACHED`; only the `COPY app/` and `COPY data/` steps ran.

16. **Kubernetes: "Users get connection refused from the catalog service. The pods are Running and Ready."**
    ```bash
    cd -                      # back to the lesson folder
    ./k8s/up.sh
    kubectl get pods
    kubectl exec client -- curl -sv -m 3 http://catalog
    ```
    ```
    * IPv4: 10.96.124.47
    * connect to 10.96.124.47 port 80 from 10.244.0.8 port 39292 failed: Connection refused
    command terminated with exit code 7
    ```
    Refused, not timed out: DNS and the network path work; nothing listens on the port the traffic is sent to.

17. Look between the Service and the pods: selector, ports, network policy.
    ```bash
    kubectl get endpointslices -l kubernetes.io/service-name=catalog
    kubectl get svc catalog -o jsonpath='{.spec.ports}{"\n"}'
    kubectl get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].ports}{"\n"}'
    ```
    ```
    catalog-qtdq8   IPv4          80      10.244.0.6,10.244.0.5   56s
    [{"name":"web","port":80,"protocol":"TCP","targetPort":80}]
    [{"containerPort":8080,"name":"http","protocol":"TCP"}]
    ```
    The selector matches (two endpoints), but `targetPort` is 80 and the container listens on 8080.

18. Point `targetPort` at the named port, and prove it with the same test that failed:
    ```bash
    kubectl patch svc catalog -p '{"spec":{"ports":[{"port":80,"targetPort":"http"}]}}'
    kubectl get endpointslices -l kubernetes.io/service-name=catalog
    kubectl exec client -- curl -s -o /dev/null -w '%{http_code}\n' http://catalog
    ```
    ```
    catalog-qtdq8   IPv4          8080    10.244.0.5,10.244.0.6   65s
    200
    ```
    Why the name? If the container port changes, the Service follows. And put the fix in Git too, or a GitOps sync puts
    the old port back. Catch it earlier with a post-deploy smoke test that calls the Service by name.

**Rahul's feedback:** strong - read the Dockerfile out loud and caught four real problems; ruled layers out in order. Gap -
"switch to Alpine" was a confident guess with no number. When asked to optimize, say first what you'd measure
(`docker history`, a profiler, a dashboard). Example score: 3 / 3 / 4 / 3 = 13 of 16.

### Round 3: CI/CD and cloud design (no lab - practise it out loud)

**"Design CI/CD and the infrastructure for a new quiz service on AWS."** Asha's answer, in order:

| Part | What she says |
|---|---|
| Clarify | Students worldwide; quiz answers and scores in Postgres, no card data; SLO 99.9% of requests over 30 days; Priya's three developers, Asha and Rahul as the platform |
| Assumptions | The [M20-L01](../../capstones/m20-l01-designing-a-production-delivery-platform/) platform exists (accounts, Terraform, EKS, Argo CD): join the golden path, don't build a second one |
| Source | Trunk-based, a pull request with one review, required checks |
| CI | Build once, test against a real Postgres, then the M18 gates: secret scan, static analysis, dependency and image scans |
| Artifact | One image with SBOM and provenance, signed with cosign, pushed to ECR, deployed by digest, never by tag |
| Delivery | CI stops at Git: commits the new digest to the deploy repo; Argo CD pulls it into each environment |
| Promotion | dev, staging, production by commits, approval before production, the same digest all the way |
| Infrastructure | Terraform modules, one state per environment and component; plan on every PR, apply exactly that saved plan |
| Data | RDS Postgres, Multi-AZ, point-in-time recovery, master password managed by RDS in Secrets Manager |
| Observability | Golden signals, an SLO for quiz submissions, burn-rate alerts paging at 14.4x (M17) |
| Secrets | No stored keys: OIDC token, a role trusting one repo and one branch; app secrets via External Secrets Operator |
| Multi-account | dev, staging, prod in separate accounts under one organization (M19); only main can assume the prod deploy role |
| Rollback | Canary rolls back on burn rate; a revert in the deploy repo (Healthy after 12 s in M15's build); expand-then-contract schema changes |
| Cost | Shares the cluster and ALB. Shared fixed items (us-east-1 list prices, checked October 2026): EKS control plane $0.10/h, NAT gateway $0.045/h + data, ALB $0.0225/h. Team and service tags, a budget alarm |
| Honest caveats | M11: both ECS tasks on one node - spread across zones on purpose. M15: one self-managed node because the sandbox denied node groups - production gets managed node groups or Karpenter across zones. One NAT gateway is a single point of failure - one per zone is worth it |
| Why EKS, not ECS? | Alone, ECS is simpler; but the platform's runtime ADR chose EKS (canaries, signed-only admission), and joining costs less than a second runtime |

**Rahul's feedback:** strong - requirements first, a clear path of one change, real trade-offs, honest caveats. Gap - no
load numbers: ask peak requests per second and data growth, then size the design from that estimate. Example score:
4 / 4 / 3 / 4 = 15 of 16.

### Debrief and checklist
Scorecard: 15 + 13 + 15 = 43 of 48 - ready, with three things to practise: **lead with the answer**, **measure before you
optimize**, **close the loop** (verify the user's path; start every design with an estimate).

- **Before:** read the job description, map its tools to this course, ask the recruiter about the rounds, prepare three STAR stories with a number.
- **During:** clarify and state assumptions, think aloud, run the cheapest check first, and say "I don't know - here's how I'd find out".
- **For a fix:** mitigate, fix, verify, prevent. **For a design:** requirements, an estimate, the path of one change, trade-offs and failure modes.
- **After:** write down every question you were asked, and redo your weakest round within a week.

## Common mistakes
- A confident guess ("switch to Alpine") instead of a measurement.
- Giving the explanation first and the direct answer last.
- Stopping a process before finding out who owns it and whether it is still needed.
- Verifying a fix only on the box (`curl localhost`) instead of the path users take.
- Using `curl -k` in production instead of fixing trust.
- Designing without a load estimate.

## Clean up
```bash
cd interview/m21-l04-full-mock-interview
./web01/down.sh
kind delete cluster --name mock
docker rmi copilot:before copilot:after
rm -rf ~/copilot-mock
```

## Next
That's the end of the course. Final practice: the 75-question interview sheet and the 10 take-home tasks in
[practice/](../../practice/README.md).
