# DevOps Course: From Linux to Kubernetes in Production

The companion repo for the **AllCsVideos DevOps course**: 21 modules, 110 videos, one running example (the
allcsvideos platform), from your first Linux shell to a secured, observed, GitOps-driven Kubernetes deployment on AWS.

Every video has a folder here with its files and a step-by-step guide, so you can repeat on your own laptop exactly
what the video does.

---

## How to use this repo

1. **Clone it once** (lecture [M01-L03](setup/m01-l03-setting-up-your-devops-lab/) shows this):
   ```bash
   git clone https://github.com/allcsnotes/Devops_Course.git
   cd Devops_Course
   ```
2. **Watch a lecture**, then open its folder (see the [lesson index](#lesson-index) below, or the **Resources** tab on
   the lecture page).
3. **Open the folder's `README.md` and follow it top to bottom.** Every lesson README has the same parts:

   | Part | What it gives you |
   |---|---|
   | What you'll learn | the goal of the lecture in a few bullets |
   | Before you start | what to install, and which earlier lesson you need |
   | Files in this folder | what each file is for |
   | Follow along | every command, in the order the video runs it, with "you should see" output |
   | Common mistakes | the traps the video warns about |
   | Clean up | how to remove only what this lesson created |
   | Next | a link to the next lecture |

   Lectures that are mostly theory have **Key ideas** and **Try it yourself** instead of the hands-on parts.
4. **Get updates** later with `git pull` in the repo folder.

> Work on a **copy**, not in the repo. When a lesson changes files (the allcsvideos app, a Terraform project), its
> README tells you to copy them somewhere like `~/allcsvideos-lab` first. Your clone stays clean, and `git pull` keeps
> working.

---

## What to install, module by module

You do **not** need everything on day one. Install tools when you reach the module that needs them. Every lab runs in
**Docker containers or a local kind cluster**, so the servers, databases and CI tools in the course never get
installed on your laptop.

| Modules | Install before you start | Notes |
|---|---|---|
| **M01** Getting Started | Docker Desktop, VS Code, Git, a free GitHub account | Set up in [M01-L03](setup/m01-l03-setting-up-your-devops-lab/), including your SSH key |
| **M02–M07** Linux, scripting, networking, Git, Docker | Nothing new | Each lab is a container (`lab/up.sh`, or a `docker run` line in the README) |
| **M08–M09** CI/CD | A GitHub account (a public repo gets free Actions minutes); optional [GitHub CLI](https://cli.github.com/) `gh` | Some lessons also offer an offline Gitea lab. A second GitHub account helps for review/approval demos |
| **M10** Cloud with AWS | An **AWS account** (a sandbox or a new account, with a billing alarm) | Commands run in **AWS CloudShell**, so nothing installs locally. Every lesson states the cost and how to delete everything |
| **M11** Terraform | Terraform **1.16.6** (in CloudShell, as the lesson shows), or the `hashicorp/terraform:1.16.6` image | [M11-L02](terraform/m11-l02-hcl-basics/) runs locally and is free |
| **M12** Ansible | Nothing new | Ansible runs inside the lab's control container |
| **M13–M15** Kubernetes | [kind](https://kind.sigs.k8s.io/) **v0.33.0**, [kubectl](https://kubernetes.io/docs/tasks/tools/) **v1.37.1**, [Helm](https://helm.sh/) (M14-L01 onwards) | Give Docker about 4 GB of memory. M15-L04 and M15-B01 use AWS EKS, which costs money |
| **M16–M17** Observability and SRE | `curl`, `jq` | Prometheus, Grafana, Loki, Tempo and k6 all run in Compose |
| **M18–M19** Security and platform | Nothing new (kind and kubectl from M13) | Scanners such as Trivy, Syft, cosign and gitleaks run as pinned containers |
| **M20–M21** Capstones and interviews | Everything above | Run one lab at a time: several labs use the same ports |

**On Windows**, use **WSL 2** (Ubuntu) with Docker Desktop's WSL integration, and clone the repo inside WSL. The
scripts are Bash and expect Linux line endings. **On macOS** some scripts need Bash 4 or newer (`brew install bash`);
the lesson says so where it matters.

**Versions are pinned.** Every image, chart and tool uses the exact version from the video (never `:latest`), so your
output matches the video. Numbers that depend on your machine, like IDs, hashes, IPs and timings, will differ, and
the READMEs point these out.

---

## Repo layout

```text
Devops_Course/
├── allcsvideos/      the running example app: storefront, API, Course Copilot, PostgreSQL, Redis (Docker Compose)
├── setup/            M01  getting started and your lab
├── linux/            M02  Linux essentials
├── scripts/          M03  Bash and Python automation
├── networking/       M04  IPs, DNS, ports, HTTP/TLS, troubleshooting
├── git/              M05  Git and pull requests
├── docker/           M06–M07  Docker fundamentals and in practice
├── ci/               M08–M09  continuous integration and delivery
├── cloud/            M10  AWS fundamentals
├── terraform/        M11  infrastructure as code
├── ansible/          M12  configuration management
├── k8s/              M13–M15  Kubernetes, Helm, Kustomize, Argo CD, EKS
├── observability/    M16–M17  metrics, logs, traces, alerts, SLOs, chaos
├── security/         M18  DevSecOps
├── platform/         M19  platform engineering, FinOps, multi-account, AI in DevOps
├── capstones/        M20  capstone builds
├── interview/        M21  interview preparation
└── practice/         practice sheets and take-home tasks
```

Each lesson folder is named after its video, for example `docker/m06-l04-the-dockerfile-line-by-line/`. In each
module the lessons (L) come first, then the build (B) that puts them together.

**The allcsvideos app** in [`allcsvideos/`](allcsvideos/) is the platform the course builds up, module by module. It
is created in [M07-B01](docker/m07-b01-containerise-the-allcsvideos-stack/), and later modules build on it. Its
[README](allcsvideos/README.md) shows how to run it with one command.

**Practice:** after Modules 2, 5, 13 and 21 there are practice sheets with broken systems to fix and worked answers.
See [`practice/`](practice/README.md).

---

## Safety first

- **Clean up after every lesson.** Each README ends with commands that remove only what that lesson created.
- **AWS costs real money.** Use a sandbox account with a billing alarm. Run each lesson's clean-up (or
  `terraform destroy`) the **same day**.
- **Every password, key and token in this repo is fake** and is labelled as a demo value. Security lessons plant fake
  keys on purpose so scanners have something to catch. Never put real secrets in your copy.

---

## Lesson index

Lessons first, then the module's build, in the order the course plays them.

### Level 1 · Foundations


**M01 · Getting Started** · folder [`setup/`](setup/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | What is DevOps | Lesson | [m01-l01-what-is-devops](setup/m01-l01-what-is-devops/) |
| L02 | DevOps, SRE and Platform Engineering | Lesson | [m01-l02-devops-sre-and-platform-engineering](setup/m01-l02-devops-sre-and-platform-engineering/) |
| L03 | Setting Up Your DevOps Lab | Lesson | [m01-l03-setting-up-your-devops-lab](setup/m01-l03-setting-up-your-devops-lab/) |
| L04 | From Laptop to Production | Lesson | [m01-l04-from-laptop-to-production](setup/m01-l04-from-laptop-to-production/) |

**M02 · Linux Essentials** · folder [`linux/`](linux/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | The Shell and the Filesystem | Lesson | [m02-l01-the-shell-and-the-filesystem](linux/m02-l01-the-shell-and-the-filesystem/) |
| L02 | Users, Groups and Permissions | Lesson | [m02-l02-users-groups-and-permissions](linux/m02-l02-users-groups-and-permissions/) |
| L03 | Processes, Signals and systemd | Lesson | [m02-l03-processes-signals-and-systemd](linux/m02-l03-processes-signals-and-systemd/) |
| L04 | Text Processing | Lesson | [m02-l04-text-processing](linux/m02-l04-text-processing/) |
| L05 | Disks, Memory and Packages | Lesson | [m02-l05-disks-memory-and-packages](linux/m02-l05-disks-memory-and-packages/) |
| L06 | SSH and Remote Servers | Lesson | [m02-l06-ssh-and-remote-servers](linux/m02-l06-ssh-and-remote-servers/) |

**M03 · Shell Scripting and Automation** · folder [`scripts/`](scripts/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | Bash Basics | Lesson | [m03-l01-bash-basics](scripts/m03-l01-bash-basics/) |
| L02 | Robust Scripts | Lesson | [m03-l02-robust-scripts](scripts/m03-l02-robust-scripts/) |
| L03 | Scheduling and Automation | Lesson | [m03-l03-scheduling-and-automation](scripts/m03-l03-scheduling-and-automation/) |
| L04 | Python for Ops | Lesson | [m03-l04-python-for-ops](scripts/m03-l04-python-for-ops/) |
| B01 | Build a Server Health-Check Toolkit | Build | [m03-b01-build-a-server-health-check-toolkit](scripts/m03-b01-build-a-server-health-check-toolkit/) |

**M04 · Networking for DevOps** · folder [`networking/`](networking/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | IP Addresses, Subnets and CIDR | Lesson | [m04-l01-ip-addresses-subnets-and-cidr](networking/m04-l01-ip-addresses-subnets-and-cidr/) |
| L02 | DNS in Practice | Lesson | [m04-l02-dns-in-practice](networking/m04-l02-dns-in-practice/) |
| L03 | Ports, TCP and Firewalls | Lesson | [m04-l03-ports-tcp-and-firewalls](networking/m04-l03-ports-tcp-and-firewalls/) |
| L04 | HTTP, TLS and Certificates | Lesson | [m04-l04-http-tls-and-certificates](networking/m04-l04-http-tls-and-certificates/) |
| L05 | The Troubleshooting Toolbox | Lesson | [m04-l05-the-troubleshooting-toolbox](networking/m04-l05-the-troubleshooting-toolbox/) |

**M05 · Git and Collaboration** · folder [`git/`](git/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | How Git Really Works | Lesson | [m05-l01-how-git-really-works](git/m05-l01-how-git-really-works/) |
| L02 | Branching Strategies | Lesson | [m05-l02-branching-strategies](git/m05-l02-branching-strategies/) |
| L03 | Merge, Rebase and Fixing Mistakes | Lesson | [m05-l03-merge-rebase-and-fixing-mistakes](git/m05-l03-merge-rebase-and-fixing-mistakes/) |
| L04 | The Pull-Request Workflow | Lesson | [m05-l04-the-pull-request-workflow](git/m05-l04-the-pull-request-workflow/) |

### Level 2 · Containers


**M06 · Docker Fundamentals** · folder [`docker/`](docker/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | VMs vs Containers | Lesson | [m06-l01-vms-vs-containers](docker/m06-l01-vms-vs-containers/) |
| L02 | Images, Layers and Registries | Lesson | [m06-l02-images-layers-and-registries](docker/m06-l02-images-layers-and-registries/) |
| L03 | Running Containers | Lesson | [m06-l03-running-containers](docker/m06-l03-running-containers/) |
| L04 | The Dockerfile, Line by Line | Lesson | [m06-l04-the-dockerfile-line-by-line](docker/m06-l04-the-dockerfile-line-by-line/) |
| L05 | Volumes and Bind Mounts | Lesson | [m06-l05-volumes-and-bind-mounts](docker/m06-l05-volumes-and-bind-mounts/) |
| L06 | Container Networking | Lesson | [m06-l06-container-networking](docker/m06-l06-container-networking/) |

**M07 · Docker in Practice** · folder [`docker/`](docker/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | Small, Fast Images | Lesson | [m07-l01-small-fast-images](docker/m07-l01-small-fast-images/) |
| L02 | Docker Compose | Lesson | [m07-l02-docker-compose](docker/m07-l02-docker-compose/) |
| L03 | Image Security | Lesson | [m07-l03-image-security](docker/m07-l03-image-security/) |
| L04 | Registries and Tagging | Lesson | [m07-l04-registries-and-tagging](docker/m07-l04-registries-and-tagging/) |
| B01 | Containerise the allcsvideos Stack | Build | [m07-b01-containerise-the-allcsvideos-stack](docker/m07-b01-containerise-the-allcsvideos-stack/) |

### Level 3 · CI/CD


**M08 · Continuous Integration** · folder [`ci/`](ci/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | What CI Is | Lesson | [m08-l01-what-ci-is](ci/m08-l01-what-ci-is/) |
| L02 | GitHub Actions Anatomy | Lesson | [m08-l02-github-actions-anatomy](ci/m08-l02-github-actions-anatomy/) |
| L03 | Build, Test and Lint | Lesson | [m08-l03-build-test-and-lint](ci/m08-l03-build-test-and-lint/) |
| L04 | Building and Pushing Images | Lesson | [m08-l04-building-and-pushing-images](ci/m08-l04-building-and-pushing-images/) |
| L05 | Secrets and OIDC | Lesson | [m08-l05-secrets-and-oidc](ci/m08-l05-secrets-and-oidc/) |

**M09 · Continuous Delivery and Releases** · folder [`ci/`](ci/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | Delivery vs Deployment | Lesson | [m09-l01-delivery-vs-deployment](ci/m09-l01-delivery-vs-deployment/) |
| L02 | Deployment Strategies | Lesson | [m09-l02-deployment-strategies](ci/m09-l02-deployment-strategies/) |
| L03 | Feature Flags | Lesson | [m09-l03-feature-flags](ci/m09-l03-feature-flags/) |
| L04 | Versioning and Rollback | Lesson | [m09-l04-versioning-and-rollback](ci/m09-l04-versioning-and-rollback/) |
| L05 | Jenkins and GitLab CI | Lesson | [m09-l05-jenkins-and-gitlab-ci](ci/m09-l05-jenkins-and-gitlab-ci/) |
| B01 | End-to-End Pipeline | Build | [m09-b01-end-to-end-pipeline](ci/m09-b01-end-to-end-pipeline/) |

### Level 4 · Cloud and Infrastructure as Code


**M10 · Cloud Fundamentals with AWS** · folder [`cloud/`](cloud/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | The Cloud Model | Lesson | [m10-l01-the-cloud-model](cloud/m10-l01-the-cloud-model/) |
| L02 | IAM | Lesson | [m10-l02-iam](cloud/m10-l02-iam/) |
| L03 | VPC Networking | Lesson | [m10-l03-vpc-networking](cloud/m10-l03-vpc-networking/) |
| L04 | Compute | Lesson | [m10-l04-compute](cloud/m10-l04-compute/) |
| L05 | Storage and Databases | Lesson | [m10-l05-storage-and-databases](cloud/m10-l05-storage-and-databases/) |
| L06 | Serverless and Managed Containers | Lesson | [m10-l06-serverless-and-managed-containers](cloud/m10-l06-serverless-and-managed-containers/) |

**M11 · Infrastructure as Code with Terraform** · folder [`terraform/`](terraform/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | Why IaC | Lesson | [m11-l01-why-iac](terraform/m11-l01-why-iac/) |
| L02 | HCL Basics | Lesson | [m11-l02-hcl-basics](terraform/m11-l02-hcl-basics/) |
| L03 | State | Lesson | [m11-l03-state](terraform/m11-l03-state/) |
| L04 | Modules | Lesson | [m11-l04-modules](terraform/m11-l04-modules/) |
| L05 | Environments and Pipelines | Lesson | [m11-l05-environments-and-pipelines](terraform/m11-l05-environments-and-pipelines/) |
| L06 | Drift, Import and the Ecosystem | Lesson | [m11-l06-drift-import-and-the-ecosystem](terraform/m11-l06-drift-import-and-the-ecosystem/) |
| B01 | Provision the allcsvideos AWS Infrastructure with Terraform | Build | [m11-b01-provision-the-allcsvideos-aws-infrastructure-with-terraform](terraform/m11-b01-provision-the-allcsvideos-aws-infrastructure-with-terraform/) |

**M12 · Configuration Management** · folder [`ansible/`](ansible/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | Ansible Basics | Lesson | [m12-l01-ansible-basics](ansible/m12-l01-ansible-basics/) |
| L02 | Ansible in Practice | Lesson | [m12-l02-ansible-in-practice](ansible/m12-l02-ansible-in-practice/) |
| L03 | Mutable vs Immutable Infrastructure | Lesson | [m12-l03-mutable-vs-immutable-infrastructure](ansible/m12-l03-mutable-vs-immutable-infrastructure/) |
| B01 | Configure a VM Fleet with Ansible | Build | [m12-b01-configure-a-vm-fleet-with-ansible](ansible/m12-b01-configure-a-vm-fleet-with-ansible/) |

### Level 5 · Kubernetes


**M13 · Kubernetes Fundamentals** · folder [`k8s/`](k8s/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | Why Orchestration | Lesson | [m13-l01-why-orchestration](k8s/m13-l01-why-orchestration/) |
| L02 | Your First Cluster | Lesson | [m13-l02-your-first-cluster](k8s/m13-l02-your-first-cluster/) |
| L03 | Pods | Lesson | [m13-l03-pods](k8s/m13-l03-pods/) |
| L04 | Deployments and ReplicaSets | Lesson | [m13-l04-deployments-and-replicasets](k8s/m13-l04-deployments-and-replicasets/) |
| L05 | Services and DNS | Lesson | [m13-l05-services-and-dns](k8s/m13-l05-services-and-dns/) |
| L06 | ConfigMaps and Secrets | Lesson | [m13-l06-configmaps-and-secrets](k8s/m13-l06-configmaps-and-secrets/) |

**M14 · Kubernetes in Practice** · folder [`k8s/`](k8s/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | Ingress and the Gateway API | Lesson | [m14-l01-ingress-and-the-gateway-api](k8s/m14-l01-ingress-and-the-gateway-api/) |
| L02 | Storage | Lesson | [m14-l02-storage](k8s/m14-l02-storage/) |
| L03 | Health and Resources | Lesson | [m14-l03-health-and-resources](k8s/m14-l03-health-and-resources/) |
| L04 | Autoscaling | Lesson | [m14-l04-autoscaling](k8s/m14-l04-autoscaling/) |
| L05 | Jobs, CronJobs and DaemonSets | Lesson | [m14-l05-jobs-cronjobs-and-daemonsets](k8s/m14-l05-jobs-cronjobs-and-daemonsets/) |
| L06 | Troubleshooting Kubernetes | Lesson | [m14-l06-troubleshooting-kubernetes](k8s/m14-l06-troubleshooting-kubernetes/) |

**M15 · Packaging and GitOps** · folder [`k8s/`](k8s/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | Helm | Lesson | [m15-l01-helm](k8s/m15-l01-helm/) |
| L02 | Kustomize | Lesson | [m15-l02-kustomize](k8s/m15-l02-kustomize/) |
| L03 | GitOps with Argo CD | Lesson | [m15-l03-gitops-with-argo-cd](k8s/m15-l03-gitops-with-argo-cd/) |
| L04 | Managed Kubernetes on EKS | Lesson | [m15-l04-managed-kubernetes-on-eks](k8s/m15-l04-managed-kubernetes-on-eks/) |
| B01 | Deploy allcsvideos to EKS with Helm and Argo CD | Build | [m15-b01-deploy-allcsvideos-to-eks-with-helm-and-argo-cd](k8s/m15-b01-deploy-allcsvideos-to-eks-with-helm-and-argo-cd/) |

### Level 6 · Observability and Reliability


**M16 · Observability** · folder [`observability/`](observability/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | The Three Pillars and What to Measure | Lesson | [m16-l01-the-three-pillars-and-what-to-measure](observability/m16-l01-the-three-pillars-and-what-to-measure/) |
| L02 | Metrics with Prometheus | Lesson | [m16-l02-metrics-with-prometheus](observability/m16-l02-metrics-with-prometheus/) |
| L03 | Dashboards with Grafana | Lesson | [m16-l03-dashboards-with-grafana](observability/m16-l03-dashboards-with-grafana/) |
| L04 | Logs | Lesson | [m16-l04-logs](observability/m16-l04-logs/) |
| L05 | Distributed Tracing | Lesson | [m16-l05-distributed-tracing](observability/m16-l05-distributed-tracing/) |
| L06 | Alerting | Lesson | [m16-l06-alerting](observability/m16-l06-alerting/) |
| B01 | Full Observability for allcsvideos | Build | [m16-b01-full-observability-for-allcsvideos](observability/m16-b01-full-observability-for-allcsvideos/) |

**M17 · SRE Practices** · folder [`observability/`](observability/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | SLIs, SLOs and Error Budgets | Lesson | [m17-l01-slis-slos-and-error-budgets](observability/m17-l01-slis-slos-and-error-budgets/) |
| L02 | Incident Response | Lesson | [m17-l02-incident-response](observability/m17-l02-incident-response/) |
| L03 | Load Testing and Capacity Planning | Lesson | [m17-l03-load-testing-and-capacity-planning](observability/m17-l03-load-testing-and-capacity-planning/) |
| L04 | Chaos Engineering and Disaster Recovery | Lesson | [m17-l04-chaos-engineering-and-disaster-recovery](observability/m17-l04-chaos-engineering-and-disaster-recovery/) |
| B01 | Game Day with SLOs, Chaos and a Postmortem | Build | [m17-b01-game-day-with-slos-chaos-and-a-postmortem](observability/m17-b01-game-day-with-slos-chaos-and-a-postmortem/) |

### Level 7 · Security and Platform Engineering


**M18 · DevSecOps** · folder [`security/`](security/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | Shift Left | Lesson | [m18-l01-shift-left](security/m18-l01-shift-left/) |
| L02 | Secrets Management | Lesson | [m18-l02-secrets-management](security/m18-l02-secrets-management/) |
| L03 | Supply-Chain Security | Lesson | [m18-l03-supply-chain-security](security/m18-l03-supply-chain-security/) |
| L04 | Kubernetes Security | Lesson | [m18-l04-kubernetes-security](security/m18-l04-kubernetes-security/) |
| L05 | Cloud Security and Compliance | Lesson | [m18-l05-cloud-security-and-compliance](security/m18-l05-cloud-security-and-compliance/) |
| B01 | A Secure Delivery Pipeline | Build | [m18-b01-a-secure-delivery-pipeline](security/m18-b01-a-secure-delivery-pipeline/) |

**M19 · Platform Engineering and Cost** · folder [`platform/`](platform/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | Internal Developer Platforms | Lesson | [m19-l01-internal-developer-platforms](platform/m19-l01-internal-developer-platforms/) |
| L02 | FinOps | Lesson | [m19-l02-finops](platform/m19-l02-finops/) |
| L03 | Multi-Environment and Multi-Account Strategy | Lesson | [m19-l03-multi-environment-and-multi-account-strategy](platform/m19-l03-multi-environment-and-multi-account-strategy/) |
| L04 | AI in DevOps | Lesson | [m19-l04-ai-in-devops](platform/m19-l04-ai-in-devops/) |

### Level 8 · Capstones and Interview Ready


**M20 · Capstone Projects** · folder [`capstones/`](capstones/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | Designing a Production Delivery Platform | Lesson | [m20-l01-designing-a-production-delivery-platform](capstones/m20-l01-designing-a-production-delivery-platform/) |
| B01 | Zero-Downtime Migration from VMs to Kubernetes | Build | [m20-b01-zero-downtime-migration-from-vms-to-kubernetes](capstones/m20-b01-zero-downtime-migration-from-vms-to-kubernetes/) |
| B02 | Disaster-Recovery Drill | Build | [m20-b02-disaster-recovery-drill](capstones/m20-b02-disaster-recovery-drill/) |
| B03 | Troubleshooting Labs | Build | [m20-b03-troubleshooting-labs](capstones/m20-b03-troubleshooting-labs/) |

**M21 · DevOps Interview Preparation** · folder [`interview/`](interview/)

| # | Lesson | Type | Folder |
|---|---|---|---|
| L01 | How DevOps Interviews Work | Lesson | [m21-l01-how-devops-interviews-work](interview/m21-l01-how-devops-interviews-work/) |
| L02 | The 60 Most-Asked DevOps and SRE Questions | Lesson | [m21-l02-the-60-most-asked-devops-and-sre-questions](interview/m21-l02-the-60-most-asked-devops-and-sre-questions/) |
| L03 | The Scenario Round | Lesson | [m21-l03-the-scenario-round](interview/m21-l03-the-scenario-round/) |
| L04 | Full Mock Interview | Lesson | [m21-l04-full-mock-interview](interview/m21-l04-full-mock-interview/) |

---

Found a problem in a lesson folder? Open an issue with the lesson ID (for example `M06-L04`) and what happened.
