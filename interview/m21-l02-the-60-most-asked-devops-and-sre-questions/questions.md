# The 60 most-asked DevOps and SRE questions, with model answers

Companion to M21-L02 of "DevOps: From Linux to Kubernetes in Production". These are questions that commonly come up in DevOps and SRE
interviews, grouped in nine blocks in course order. It is not a ranked list and no frequency statistics are implied. Each answer names the
lesson that teaches it, and the final 75-question practice sheet is in [practice/](../../practice/README.md).

How to use it: read the question, answer out loud in two or three sentences, then compare. Say every key point in your own words.

## Block 1: Linux and the shell (Q1-Q7)

### Q1. What is the difference between a hard link and a symbolic link?

**Model answer.** A hard link is a second name for the same inode, so the data lives until the last name is gone, but it can't cross filesystems or point to a directory. A symbolic link is a small file that holds a path: it can point anywhere, but it breaks if the target moves.

**Key points:** hard link: a second name for the same inode; data lives until the last name is gone; symlink: a small file holding a path; breaks if the target moves.

**Real output in the course:** captured in [M02-L01](../../linux/m02-l01-the-shell-and-the-filesystem/).

**Covered in:** [M02-L01](../../linux/m02-l01-the-shell-and-the-filesystem/) (The Shell and the Filesystem).

### Q2. A web app can't write to its upload folder, and someone suggests chmod 777. What do you do?

**Model answer.** I check which user the app runs as and who owns the folder, then grant exactly that: the app user as owner, or a shared group, with 750 on folders and 640 on files. 777 lets every account on the server write there.

**Key points:** which user runs it? who owns the folder?; grant owner or group access; 750 on folders · 640 on files; 777 = every account can write.

**Follow-up they may ask:** What do the three digits mean? Owner · group · others, each adding read 4, write 2, execute 1.

**Covered in:** [M02-L02](../../linux/m02-l02-users-groups-and-permissions/) (Users, Groups and Permissions).

### Q3. How do you stop a process safely?

**Model answer.** I send SIGTERM first, so it can clean up and exit, wait a few seconds, and use SIGKILL only if it won't stop, because SIGKILL can't be caught. If it's a service, I use systemctl stop, so systemd handles it.

**Key points:** SIGTERM first: let it clean up; wait a few seconds; SIGKILL last: it can't be caught; a service: systemctl stop.

**Real output in the course:** captured in [M02-L03](../../linux/m02-l03-processes-signals-and-systemd/).

**Covered in:** [M02-L03](../../linux/m02-l03-processes-signals-and-systemd/) (Processes, Signals and systemd).

### Q4. What is a zombie process, and how do you get rid of one?

**Model answer.** A zombie has already exited, but its parent hasn't collected its exit status, so it stays in the process table with state Z. You can't kill what's already dead: fix or end the parent, and the zombie goes with it.

**Key points:** already exited; exit status never collected; state Z · <defunct>; kill -9 does nothing; fix or end the parent.

**Real output in the course:** captured in [M02-L03](../../linux/m02-l03-processes-signals-and-systemd/).

**Covered in:** [M02-L03](../../linux/m02-l03-processes-signals-and-systemd/) (Processes, Signals and systemd).

### Q5. The disk is full. How do you find what is using it?

**Model answer.** df -h shows which filesystem is full, then du, sorted, walks down to the biggest folders. If df says full but du can't find it, a deleted file is still held open, and lsof +L1 finds the process. And if there's space but writes fail, check inodes with df -i.

**Key points:** df -h: which filesystem; du | sort: the biggest folders; they disagree: lsof +L1; space, but no writes: df -i.

**Follow-up they may ask:** How do you free that space? Restart or reload the process holding it. Next time, truncate the log instead of deleting it.

**Real output in the course:** captured in [M02-L05](../../linux/m02-l05-disks-memory-and-packages/).

**Covered in:** [M02-L05](../../linux/m02-l05-disks-memory-and-packages/) (Disks, Memory and Packages).

### Q6. How would you find the top ten IP addresses hitting a web server?

**Model answer.** Take the first field of the access log with awk, sort it so identical addresses sit together, count them with uniq -c, sort the counts in reverse numeric order, and keep the first ten with head.

**Key points:** awk '{print $1}' access.log; | sort; | uniq -c; | sort -rn; | head -n 10.

**Covered in:** [M02-L04](../../linux/m02-l04-text-processing/) (Text Processing).

### Q7. What does set -euo pipefail do, and is it enough?

**Model answer.** -e exits when a command fails, -u makes unset variables an error, and pipefail fails a pipeline if any part fails. It's not enough: -e is skipped inside if conditions and && or || lists, so I still check important commands, clean up with a trap on EXIT, and run shellcheck.

**Key points:** -e: exit on a failed command; -u: unset variable = error; pipefail: any stage fails it; -e skipped in if, && and ||; + trap … EXIT + shellcheck.

**Covered in:** [M03-L02](../../scripts/m03-l02-robust-scripts/) (Robust Scripts).

## Block 2: Networking (Q8-Q13)

### Q8. How many usable hosts fit in a /27?

**Model answer.** A /27 leaves 5 host bits, so 32 addresses. Minus the network and broadcast addresses, that's 30 usable hosts, or 27 on AWS, which reserves 5 per subnet.

**Key points:** 32 − 27 = 5 host bits → 32; − network − broadcast = 30; on AWS: 27 (5 reserved).

**Real output in the course:** captured in [M04-L01](../../networking/m04-l01-ip-addresses-subnets-and-cidr/).

**Covered in:** [M04-L01](../../networking/m04-l01-ip-addresses-subnets-and-cidr/) (IP Addresses, Subnets and CIDR).

### Q9. You changed a DNS record, but some users reach the old server for hours. Why?

**Model answer.** Resolvers cache the old record for its full TTL. So lower the TTL at least one old TTL before the move, change the record, check it with dig at the authoritative server and a resolver, keep the old server up until its traffic drains, then raise the TTL again.

**Key points:** resolvers cache it for the TTL; lower the TTL one old TTL ahead; change, then verify with dig; keep the old server until it drains.

**Real output in the course:** captured in [M04-L02](../../networking/m04-l02-dns-in-practice/).

**Covered in:** [M04-L02](../../networking/m04-l02-dns-in-practice/) (DNS in Practice).

### Q10. What happens when you open https://allcsvideos.com in a browser?

**Model answer.** DNS turns the name into an address, and the browser opens a TCP connection to port 443. A TLS 1.3 handshake follows: the server sends its certificate chain, the browser checks it up to a trusted root, the name and the dates, and both sides derive session keys. Then the HTTP request travels encrypted, usually to a reverse proxy in front of the app.

**Key points:** DNS: name → IP; TCP to port 443; TLS: certificate checked, keys agreed; encrypted HTTP → reverse proxy → app.

**Covered in:** [M04-L04](../../networking/m04-l04-http-tls-and-certificates/) (HTTP, TLS and Certificates).

### Q11. Connection refused versus connection timed out: what is the difference?

**Model answer.** Refused means the packet reached the host but nothing listens on that port, so its kernel replied with a reset. A timeout means nothing came back at all, usually a firewall or security group dropping the packet. So for refused I check ss on the server; for a timeout, the firewall rules and the routes.

**Key points:** refused: arrived, nothing listening → RST; timeout: no reply at all; usually a firewall or security group; ss -tulpn · or the rules + routes.

**Real output in the course:** captured in [M04-L03](../../networking/m04-l03-ports-tcp-and-firewalls/).

**Covered in:** [M04-L03](../../networking/m04-l03-ports-tcp-and-firewalls/) (Ports, TCP and Firewalls).

### Q12. What is the difference between a 502 and a 504?

**Model answer.** Both come from the proxy, not the app. A 502, bad gateway, means the proxy couldn't get a valid answer from its upstream, like a refused connection. A 504, gateway timeout, means the upstream didn't answer in time. Either way, the proxy's error log says which upstream, and why.

**Key points:** both come from the proxy; 502: the upstream failed; 504: the upstream was too slow; read the proxy's error log.

**Covered in:** [M04-L05](../../networking/m04-l05-the-troubleshooting-toolbox/) (The Troubleshooting Toolbox).

### Q13. A service is unreachable. Which tools do you use, and in what order?

**Model answer.** I work outside-in, one layer at a time: dig for the name, ping or traceroute for the path, knowing ICMP may be blocked, then nc or curl to the port, openssl s_client for the certificate, curl's timings for HTTP, and finally the proxy and app logs.

**Key points:** 1 · dig: the name; 2 · ping / traceroute: the path; 3 · nc -zv / curl -v: the port; 4 · openssl s_client: TLS; 5 · curl -w timings → logs.

**Covered in:** [M04-L05](../../networking/m04-l05-the-troubleshooting-toolbox/) (The Troubleshooting Toolbox).

## Block 3: Git (Q14-Q17)

### Q14. Merge or rebase: what is the difference, and when do you use each?

**Model answer.** A merge joins two histories with a merge commit and rewrites nothing. A rebase replays your commits on top of the new base, so history is linear, but the commits get new hashes. So I rebase only my own branch before I share it, and never a branch others have pulled.

**Key points:** merge: joins, rewrites nothing; rebase: replays on a new base; linear history, new hashes; never rebase a shared branch.

**Follow-up they may ask:** You rebased a branch you had pushed. How do you push it? Git push --force-with-lease: it refuses to overwrite commits you have not seen.

**Covered in:** [M05-L03](../../git/m05-l03-merge-rebase-and-fixing-mistakes/) (Merge, Rebase and Fixing Mistakes).

### Q15. What is the difference between git reset and git revert?

**Model answer.** Reset moves the branch back and rewrites history, so I use it only on local commits nobody else has. Revert adds a new commit that undoes an old one, so it's the safe way to undo anything already pushed. And if a reset goes wrong, the reflog brings the commits back.

**Key points:** reset: moves the branch, rewrites; local commits only; revert: a new commit that undoes; git reflog rescues a bad reset.

**Real output in the course:** captured in [M05-L03](../../git/m05-l03-merge-rebase-and-fixing-mistakes/).

**Covered in:** [M05-L03](../../git/m05-l03-merge-rebase-and-fixing-mistakes/) (Merge, Rebase and Fixing Mistakes).

### Q16. GitFlow or trunk-based development: which would you choose?

**Model answer.** It depends on how we ship. For a web service deployed continuously, trunk-based: short-lived branches, feature flags and CI, because small daily merges keep integration cheap. GitFlow or release branches fit software where several shipped versions need maintaining, like a mobile app.

**Key points:** it depends how you ship; continuous web service → trunk-based; short branches + flags + CI; many versions → release branches.

**Covered in:** [M05-L02](../../git/m05-l02-branching-strategies/) (Branching Strategies).

### Q17. How do you stop a bad change from reaching main?

**Model answer.** Protect main so nobody pushes to it directly, require a pull request with an approval, and code owners for sensitive paths. Require CI checks to pass on a branch that's up to date with main, and apply the rules to admins too.

**Key points:** protected main: no direct pushes; pull request + approval + CODEOWNERS; required CI checks, up to date; admins included.

**Covered in:** [M05-L04](../../git/m05-l04-the-pull-request-workflow/) (The Pull-Request Workflow).

## Block 4: Docker and containers (Q18-Q24)

### Q18. What is a container, and how is it different from a virtual machine?

**Model answer.** A container is an ordinary Linux process, isolated by namespaces, limited by cgroups, with its own root filesystem from an image. Containers share the host kernel, so they start in a fraction of a second. A VM boots its own kernel, which is heavier, but a stronger isolation boundary.

**Key points:** a container is a process; namespaces + cgroups; shares the host kernel: starts fast; VM: own kernel, stronger boundary.

**Covered in:** [M06-L01](../../docker/m06-l01-vms-vs-containers/) (VMs vs Containers).

### Q19. Image versus container, and why does changing one Dockerfile line rebuild everything after it?

**Model answer.** An image is a read-only stack of layers plus a config; a container is a running process with a thin writable layer on top. Each layer builds on the one before, so changing one instruction invalidates the cache for every instruction after it. So copy and install the dependency files before you copy the source.

**Key points:** image: read-only layers + config; container: + a thin writable layer; one change → rebuild all after it; dependencies first, source last.

**Covered in:** [M06-L02](../../docker/m06-l02-images-layers-and-registries/) (Images, Layers and Registries).

### Q20. What is the difference between CMD and ENTRYPOINT, and why use exec form?

**Model answer.** ENTRYPOINT is the fixed program, and CMD gives its default arguments, which docker run arguments replace. Exec form matters because shell form wraps the command in /bin/sh -c, so the shell becomes PID 1 and SIGTERM never reaches the app.

**Key points:** ENTRYPOINT: the program; CMD: default args, replaced by docker run; shell form: /bin/sh -c is PID 1; exec form: SIGTERM reaches the app.

**Covered in:** [M06-L04](../../docker/m06-l04-the-dockerfile-line-by-line/) (The Dockerfile, Line by Line).

### Q21. A container takes ten seconds to stop and exits with code 137. What is going on?

**Model answer.** 137 is 128 plus 9: the process was killed by SIGKILL. Out of memory is one cause, but here docker stop sent SIGTERM, waited out the grace period, then killed it. So the app never handled SIGTERM, often because it runs as PID 1. Add a SIGTERM handler, use exec form, or run it with --init.

**Key points:** 137 = 128 + 9: SIGKILL; out of memory is one cause; SIGTERM ignored → grace period → kill; handle SIGTERM · --init.

**Follow-up they may ask:** How do you tell an OOM kill from a slow stop? Docker inspect: State.OOMKilled. In Kubernetes: Last State, Reason: OOMKilled.

**Real output in the course:** captured in [M06-L03](../../docker/m06-l03-running-containers/).

**Covered in:** [M06-L03](../../docker/m06-l03-running-containers/) (Running Containers).

### Q22. How do you keep a containerized database's data safe? Volume or bind mount?

**Model answer.** Database data goes in a named volume, which Docker manages and which outlives any container. A bind mount maps a host path you choose, for code and config. And a volume isn't a backup: dump with the database's own tool, and test the restore.

**Key points:** named volume: outlives the container; bind mount: code + config; a volume is not a backup; dump + test the restore.

**Covered in:** [M06-L05](../../docker/m06-l05-volumes-and-bind-mounts/) (Volumes and Bind Mounts).

### Q23. Two containers: the app cannot reach the database at localhost. Why?

**Model answer.** Each container has its own network namespace, so localhost is the app container itself. Put both on a user-defined network, where Docker's DNS resolves container names, point the app at the database by name, and publish only the front end.

**Key points:** its own network namespace; localhost = the container itself; a user-defined network; call it by name: Docker's DNS.

**Covered in:** [M06-L06](../../docker/m06-l06-container-networking/) (Container Networking).

### Q24. How would you make a slow, one gigabyte image small and fast to build?

**Model answer.** A multi-stage build, so only the runtime and the app ship. Order the steps from least to most changing, dependencies before source, and add a BuildKit cache mount. Then pick the smallest base the team can still debug and patch, and measure size and rebuild time at every step.

**Key points:** multi-stage: ship runtime + app only; dependencies before source; BuildKit cache mount; smallest base you can debug; measure every step.

**Covered in:** [M07-L01](../../docker/m07-l01-small-fast-images/) (Small, Fast Images).

## Block 5: CI/CD and releases (Q25-Q31)

### Q25. What is continuous integration, and how can you tell whether a team really does it?

**Model answer.** CI means everyone merges into main at least daily, and every commit triggers an automated build and tests that answer in about ten minutes. I'd check that branches are short-lived, a broken main is fixed or reverted in minutes, and the tests are trusted. A CI server alone isn't CI.

**Key points:** merge to main at least daily; every commit: build + tests, ~10 min; short-lived branches; a broken main is fixed in minutes.

**Covered in:** [M08-L01](../../ci/m08-l01-what-ci-is/) (What CI Is).

### Q26. Walk me through a GitHub Actions workflow. What runs where?

**Model answer.** A workflow is a YAML file; its on key lists the events that start it. Jobs run in parallel on fresh runners chosen by runs-on, unless needs orders them. Each job runs its steps in order, shell commands or actions, and I pin third-party actions to a commit SHA.

**Key points:** on: the trigger events; jobs: parallel, fresh runners (runs-on); needs: orders jobs; steps run in order; pin actions to a commit SHA.

**Covered in:** [M08-L02](../../ci/m08-l02-github-actions-anatomy/) (GitHub Actions Anatomy).

### Q27. Continuous delivery versus continuous deployment: and how do you promote a release?

**Model answer.** With continuous delivery, every green change is releasable, and production is a one-click decision. Continuous deployment ships every green change automatically. Either way, build the image once and promote that same digest from staging to production, never a rebuild.

**Key points:** delivery: releasable, a person clicks; deployment: ships automatically; build once; promote the same digest.

**Follow-up they may ask:** Why not just deploy :latest? A moving label: you can't tell what runs, or roll back to it.

**Covered in:** [M09-L01](../../ci/m09-l01-delivery-vs-deployment/) (Delivery vs Deployment).

### Q28. Rolling, blue-green or canary: how do you choose?

**Model answer.** Rolling replaces instances a few at a time: cheap, but old and new run side by side. Blue-green runs a full second environment and switches traffic at once, so rollback is one switch. Canary sends a small slice of traffic to the new version and checks its metrics before going further. It's best for risky changes.

**Key points:** rolling: a few at a time, cheap; blue-green: a full copy, one switch; canary: a small slice of traffic; metrics decide.

**Covered in:** [M09-L02](../../ci/m09-l02-deployment-strategies/) (Deployment Strategies).

### Q29. What is the difference between deploying and releasing, and how do feature flags help?

**Model answer.** Deploying puts a build on servers; releasing exposes a feature to users. With flags, code ships dark and is turned on at runtime, for staff, then a percentage, with no redeploy, and an ops flag works as a kill switch. Every flag needs an owner and an expiry.

**Key points:** deploy ≠ release; ship dark, enable at runtime; staff → a percentage; kill switches; owner + expiry.

**Covered in:** [M09-L03](../../ci/m09-l03-feature-flags/) (Feature Flags).

### Q30. How do you make a release that changes the database safe to roll back?

**Model answer.** Expand, migrate, contract: add the new column first, in a way the old release still works with, move the data, and drop the old column only a release later. Then a rollback is just the previous image digest, and you take a backup before anything destructive.

**Key points:** expand → migrate → contract; the old release still works; drop old columns a release later; rollback = the previous digest.

**Covered in:** [M09-L04](../../ci/m09-l04-versioning-and-rollback/) (Versioning and Rollback).

### Q31. How do you measure software delivery performance?

**Model answer.** With the five DORA metrics. Throughput: change lead time, deployment frequency, and failed deployment recovery time. Instability: change fail rate and deployment rework rate. Track them as trends to improve, not as targets.

**Key points:** change lead time; deployment frequency; failed deployment recovery time; change fail rate; deployment rework rate; trends, not targets.

**Follow-up they may ask:** What happened to MTTR? Replaced by failed deployment recovery time in 2023 (dora.dev).

**Covered in:** [M01-L01](../../setup/m01-l01-what-is-devops/) (What is DevOps).

## Block 6: Cloud, IaC and config (Q32-Q38)

### Q32. What makes a subnet public or private on AWS?

**Model answer.** Only its route table. A public subnet sends 0.0.0.0/0 to an internet gateway, a private one sends it to a NAT gateway for outbound-only traffic, and an isolated one keeps just the local route. Then security groups chain by reference: load balancer, app, database.

**Key points:** the route table decides; 0.0.0.0/0 → internet gateway: public; → NAT gateway: private; local route only: isolated.

**Covered in:** [M10-L03](../../cloud/m10-l03-vpc-networking/) (VPC Networking).

### Q33. How do you give an application on EC2 access to an S3 bucket?

**Model answer.** Never with access keys on the box. Create an IAM role that only EC2 can assume, attach it through an instance profile, and give it a policy for just the actions it needs on that bucket. The SDK then picks up temporary credentials that rotate on their own.

**Key points:** no keys on the instance; IAM role + instance profile; least privilege: one bucket; temporary, rotating credentials.

**Covered in:** [M10-L02](../../cloud/m10-l02-iam/) (IAM).

### Q34. Design a web tier that survives losing an instance, or a whole availability zone.

**Model answer.** An Auto Scaling group from a versioned launch template, in private subnets across at least two availability zones, behind an Application Load Balancer with health checks. Unhealthy instances get replaced, a lost zone's traffic shifts to the other, and target tracking scales between a minimum and a maximum.

**Key points:** Auto Scaling group across ≥ 2 AZs; load balancer + health checks; unhealthy → replaced; a lost zone → the others take over.

**Follow-up they may ask:** And the database? RDS Multi-AZ: a standby in another zone, automatic failover.

**Covered in:** [M10-L04](../../cloud/m10-l04-compute/) (Compute).

### Q35. Why does Terraform have a plan step?

**Model answer.** Terraform is declarative: you describe the end state, and it diffs that against the state and reality. The plan shows that diff before anything changes: plus to create, tilde to update, minus to destroy, minus plus to replace. So the team reviews it in the pull request and applies exactly what was approved.

**Key points:** declarative: code vs state + reality; + create · ~ update · - destroy; reviewed in the pull request; apply exactly what was approved.

**Covered in:** [M11-L01](../../terraform/m11-l01-why-iac/) (Why IaC).

### Q36. What is Terraform state, and how do you manage it in a team?

**Model answer.** State maps the addresses in your code to real resource IDs. In a team it lives in a remote backend, like S3 with versioning, encryption and locking, one state per environment and component. Since Terraform 1.11, S3 locks natively with use_lockfile, so a DynamoDB table isn't needed anymore.

**Key points:** code address → real resource ID; remote · versioned · encrypted · locked; one state per environment; use_lockfile (1.11+): no DynamoDB.

**Real output in the course:** captured in [M11-L03](../../terraform/m11-l03-state/).

**Covered in:** [M11-L03](../../terraform/m11-l03-state/) (State).

### Q37. What is drift, and how do you handle it?

**Model answer.** Drift is when real infrastructure no longer matches the code, usually after a manual change. A scheduled plan with -detailed-exitcode finds it. For each drift I either revert it with an apply, or adopt it into the code through a pull request, and I prevent it with read-only console access.

**Key points:** reality ≠ code; usually a manual change; scheduled plan -detailed-exitcode; revert it, or adopt it in code.

**Real output in the course:** captured in [M11-L06](../../terraform/m11-l06-drift-import-and-the-ecosystem/).

**Covered in:** [M11-L06](../../terraform/m11-l06-drift-import-and-the-ecosystem/) (Drift, Import and the Ecosystem).

### Q38. Ansible or Terraform: when do you use which? And what does idempotent mean?

**Model answer.** Terraform provisions infrastructure, declaratively, with state. Ansible configures what runs on servers, over SSH, without agents. Both should be idempotent: a second run changes nothing, which I prove by running twice and seeing changed equals zero. For stateless app servers, I'd rather bake an image and replace instances.

**Key points:** Terraform: provision, with state; Ansible: configure, agentless, over SSH; idempotent: a 2nd run changes nothing; proof: changed=0.

**Covered in:** [M12-L01](../../ansible/m12-l01-ansible-basics/) (Ansible Basics).

## Block 7: Kubernetes (Q39-Q46)

### Q39. What happens when you run kubectl apply on a Deployment?

**Model answer.** kubectl sends the object to the API server, which authenticates you, checks RBAC, and stores the desired state in etcd. The Deployment and ReplicaSet controllers create pods, the scheduler binds each one to a node, and that node's kubelet starts the containers. Then the controllers keep reconciling.

**Key points:** API server: auth + RBAC; stored in etcd; controllers → pods; scheduler → node; kubelet → containers; and it keeps reconciling.

**Covered in:** [M13-L02](../../k8s/m13-l02-your-first-cluster/) (Your First Cluster).

### Q40. What happens during a rolling update, and how do you make it safe?

**Model answer.** Changing the pod template creates a new ReplicaSet, scaled up while the old one scales down, within max surge and max unavailable, counting only ready pods. So add a readiness probe, use surge with zero unavailable, and roll back with rollout undo.

**Key points:** a new ReplicaSet scales up; only Ready pods count; a readiness probe; maxUnavailable: 0; kubectl rollout undo.

**Real output in the course:** captured in [M13-L04](../../k8s/m13-l04-deployments-and-replicasets/).

**Covered in:** [M13-L04](../../k8s/m13-l04-deployments-and-replicasets/) (Deployments and ReplicaSets).

### Q41. A pod calls another service by name. How does that request reach a pod?

**Model answer.** The pod's resolv.conf points at CoreDNS, which resolves the Service name to a stable cluster IP. Then kube-proxy rules on the node rewrite that connection to one ready pod from the Service's endpoints, chosen per connection.

**Key points:** resolv.conf → CoreDNS; name → a stable ClusterIP; kube-proxy rules on the node; one ready pod, per connection.

**Covered in:** [M13-L05](../../k8s/m13-l05-services-and-dns/) (Services and DNS).

### Q42. What is the difference between liveness and readiness probes?

**Model answer.** Readiness decides whether a pod gets traffic: when it fails, the pod leaves the Service endpoints. Liveness restarts a stuck container, so it must check only the process, never a dependency. A startup probe protects slow starters. The defaults: every 10 seconds, a 1 second timeout, and 3 failures.

**Key points:** readiness: traffic in or out; liveness: restart if stuck; never check dependencies in liveness; startup: slow starters; defaults: every 10 s · timeout 1 s · 3 failures.

**Covered in:** [M14-L03](../../k8s/m14-l03-health-and-resources/) (Health and Resources).

### Q43. How do requests and limits affect a pod?

**Model answer.** Requests are what the scheduler reserves; limits are enforced by cgroups. Over its CPU limit, a container is throttled; over its memory limit, it's OOMKilled, exit code 137. Together they set the QoS class that decides who's evicted first.

**Key points:** requests: what the scheduler reserves; limits: enforced; over CPU → throttled; over memory → OOMKilled, 137; QoS class: eviction order.

**Follow-up they may ask:** Why does the HPA need requests? CPU utilization is a percentage of the request. No request, nothing to divide by.

**Real output in the course:** captured in [M14-L06](../../k8s/m14-l06-troubleshooting-kubernetes/).

**Covered in:** [M14-L03](../../k8s/m14-l03-health-and-resources/) (Health and Resources).

### Q44. A pod is in CrashLoopBackOff. Walk me through it, briefly.

**Model answer.** get pods for restarts and the node, describe for the last state's exit code and the events, then logs with --previous. Exit code 1 points to the app or its config, so compare with the last good version; 137 means OOMKilled. Lesson 3 walks through it in full.

**Key points:** get pods: restarts; describe: exit code + events; logs --previous; exit 1 → app or config · 137 → OOM.

**Real output in the course:** captured in [M14-L06](../../k8s/m14-l06-troubleshooting-kubernetes/).

**Covered in:** [M14-L06](../../k8s/m14-l06-troubleshooting-kubernetes/) (Troubleshooting Kubernetes).

### Q45. Is a Kubernetes Secret secure?

**Model answer.** Not by default: it's only base64-encoded, and stored in plain text in etcd. So enable encryption at rest, restrict get, list and watch on Secrets with RBAC, and keep the real values in a manager like Vault, synced in by External Secrets Operator, so no plain secret lands in git.

**Key points:** base64 is not encryption; plain text in etcd; encryption at rest; RBAC on get · list · watch; Vault + External Secrets.

**Covered in:** [M13-L06](../../k8s/m13-l06-configmaps-and-secrets/) (ConfigMaps and Secrets).

### Q46. What is GitOps, and how is it different from kubectl apply in a pipeline?

**Model answer.** GitOps keeps the desired state in git, and an agent inside the cluster, like Argo CD, pulls and reconciles it continuously. So the pipeline needs no cluster credentials, drift is detected and healed, every change is a reviewed commit, and rollback is a git revert.

**Key points:** desired state in git; an in-cluster agent pulls (Argo CD); no cluster credentials in CI; drift self-heals; rollback = git revert.

**Follow-up they may ask:** Helm or Kustomize? Helm: versioned charts, to package and share. Kustomize: plain YAML, an overlay per environment.

**Covered in:** [M15-L03](../../k8s/m15-l03-gitops-with-argo-cd/) (GitOps with Argo CD).

## Block 8: Observability, SRE and incidents (Q47-Q53)

### Q47. What is the difference between DevOps and SRE?

**Model answer.** DevOps is a culture of shared ownership between development and operations. SRE is one concrete way to practise it, with SLOs, error budgets and engineering that cuts toil. And platform engineering packages those practices into self-service golden paths.

**Key points:** DevOps: a culture of shared ownership; SRE: one concrete practice; SLOs + error budgets; less toil; platform: golden paths.

**Covered in:** [M01-L02](../../setup/m01-l02-devops-sre-and-platform-engineering/) (DevOps, SRE and Platform Engineering).

### Q48. You're launching a new service. What do you measure?

**Model answer.** From the user's side, the golden signals: rate, errors, latency percentiles from histograms, and saturation of whatever runs out first. Underneath, utilization, saturation and errors for each resource. Plus structured logs with a trace ID, and traces. And I alert on symptoms, not on CPU.

**Key points:** rate · errors · latency percentiles; + saturation = golden signals; USE for each resource; logs with a trace ID; alert on symptoms.

**Covered in:** [M16-L01](../../observability/m16-l01-the-three-pillars-and-what-to-measure/) (The Three Pillars and What to Measure).

### Q49. How does Prometheus collect metrics, and how do you get the error rate and p95 latency?

**Model answer.** Prometheus pulls: it scrapes each target's metrics endpoint on an interval. The error rate is the rate of 5xx requests divided by the rate of all requests. For p95, sum the histogram bucket rates by le and use histogram_quantile. And keep label values bounded.

**Key points:** pull: scrape /metrics; rate(5xx) / rate(all); histogram_quantile(0.95, …); sum by (le) (rate(…_bucket[5m])).

**Covered in:** [M16-L02](../../observability/m16-l02-metrics-with-prometheus/) (Metrics with Prometheus).

### Q50. How do you design alerting that people trust?

**Model answer.** Page only on symptoms users feel, like error ratio and latency, each with a for duration and a runbook. Causes go to dashboards and tickets. Alertmanager groups by service, routes by severity, inhibits duplicates and silences planned work. And every page gets reviewed.

**Key points:** page on symptoms users feel; for: duration + a runbook; causes → dashboards; group · route · inhibit · silence; review every page.

**Covered in:** [M16-L06](../../observability/m16-l06-alerting/) (Alerting).

### Q51. What are SLIs, SLOs and error budgets, and how do you alert on them?

**Model answer.** An SLI is good events over valid events. The SLO is its target over a window, like 99.9 percent over 30 days, and the error budget is the rest: 0.1 percent. I alert on burn rate with two windows: 14.4 times over an hour, confirmed over 5 minutes, pages someone, and slow burns open tickets.

**Key points:** SLI = good / valid events; SLO: 99.9% over 30 days; error budget: the other 0.1%; burn rate: fast → page · slow → ticket.

**Covered in:** [M17-L01](../../observability/m17-l01-slis-slos-and-error-budgets/) (SLIs, SLOs and Error Budgets).

### Q52. What roles does an incident need, and what makes a postmortem blameless?

**Model answer.** An incident commander who coordinates and decides, someone who leads operations and works the fix, and a comms lead who updates the status page. Mitigate first, and keep a timestamped timeline. A blameless postmortem asks how the system let this happen, not who did it, and every action item gets an owner.

**Key points:** incident commander: decides; operations lead: the fix; comms lead: status page; mitigate first; blameless: how, not who; every action has an owner.

**Covered in:** [M17-L02](../../observability/m17-l02-incident-response/) (Incident Response).

### Q53. What are RTO and RPO, and how do you know you can recover?

**Model answer.** RTO is how long recovery may take; RPO is how much data you can afford to lose, measured in time. Agree both with the business, keep backups off-site with continuous WAL archiving, and restore them on a schedule, timing the RTO and measuring the RPO. A backup you've never restored isn't a backup.

**Key points:** RTO: time to recover; RPO: data you can lose; agreed with the business; scheduled restore drills; untested backup ≠ backup.

**Covered in:** [M17-L04](../../observability/m17-l04-chaos-engineering-and-disaster-recovery/) (Chaos Engineering and Disaster Recovery).

## Block 9: Security, platform and cost (Q54-Q60)

### Q54. What does shift left mean, and where does security go in a pipeline?

**Model answer.** Finding problems at the earliest, cheapest stage: secret scanning in pre-commit and CI, SAST and dependency scans at build, image scans and SBOMs at package, IaC scans and admission policies at deploy. Gates block only on high-confidence, fixable findings, and exceptions expire.

**Key points:** earliest stage = cheapest fix; commit: secret scans; build: SAST + dependencies; package: image scan + SBOM; deploy: IaC + admission policies; block on fixable findings.

**Covered in:** [M18-L01](../../security/m18-l01-shift-left/) (Shift Left).

### Q55. A developer pushed an AWS key to a public repository. What do you do?

**Model answer.** Revoke or rotate the key first, because it's compromised the moment it's public, and check CloudTrail for what it did. Then clean the history with git filter-repo. Then prevent a repeat: short-lived credentials from a secrets manager, pre-commit hooks and push protection.

**Key points:** revoke / rotate first; CloudTrail: what did it do?; clean the history (git filter-repo); short-lived secrets + push protection.

**Covered in:** [M18-L02](../../security/m18-l02-secrets-management/) (Secrets Management).

### Q56. How should a CI pipeline get access to the cloud?

**Model answer.** No long-lived keys. The job requests a short-lived OIDC token, and the cloud role trusts it only for one audience and a subject pinned to one repository and branch, or a protected environment. The credentials expire with the job.

**Key points:** no long-lived keys; an OIDC token per job; trust: one audience + repo + branch; credentials expire with the job.

**Covered in:** [M08-L05](../../ci/m08-l05-secrets-and-oidc/) (Secrets and OIDC).

### Q57. How would you secure the software supply chain of a container image?

**Model answer.** Lock every dependency with versions and hashes, pin base images by digest, scan in CI, and generate an SBOM for every release. Sign the image digest with cosign, attach the SBOM and provenance as signed attestations, and verify signatures before anything deploys.

**Key points:** lock dependencies + hashes; pin base images by digest; scan + an SBOM per release; sign with cosign + provenance; verify before deploy.

**Covered in:** [M18-L03](../../security/m18-l03-supply-chain-security/) (Supply-Chain Security).

### Q58. A pod in your cluster is compromised. What limits the damage?

**Model answer.** Layers. Least-privilege RBAC, with no service account token mounted unless it's needed, and default-deny network policies that allow only the paths it needs, including DNS. The restricted Pod Security Standard, so it can't escape to the node, and admission policies that only admit signed, pinned images.

**Key points:** least-privilege RBAC, no auto token; default-deny NetworkPolicy; restricted Pod Security Standard; admission: signed images only.

**Covered in:** [M18-L04](../../security/m18-l04-kubernetes-security/) (Kubernetes Security).

### Q59. What is an internal developer platform, and how do you know it is working?

**Model answer.** A product that gives teams self-service golden paths over shared capabilities, with a portal like Backstage as its front door. It's working when lead time for new services drops, adoption grows without a mandate, and DORA metrics and developer satisfaction improve.

**Key points:** the platform is a product; self-service golden paths; a portal (Backstage) = front door; lead time drops; adoption without a mandate.

**Covered in:** [M19-L01](../../platform/m19-l01-internal-developer-platforms/) (Internal Developer Platforms).

### Q60. Our cloud bill doubled. What do you do?

**Model answer.** First make cost visible and owned: enforce tags, allocate cost per team and per unit, and find out whether it's usage or waste. Then rightsize from measured usage, switch off idle and non-production resources, check data transfer, and only then buy Savings Plans for the steady baseline.

**Key points:** tags + owners; cost per team + per unit; usage, or waste?; rightsize · switch off idle; check data transfer; Savings Plans last.

**Covered in:** [M19-L02](../../platform/m19-l02-finops/) (FinOps).
