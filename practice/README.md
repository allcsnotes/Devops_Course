# Practice sheets

Five practice sheets that come after certain modules. Each one gives you a broken system, or a set of tasks, and a
hint plus a worked answer with the real output for every task. Try each task yourself before you open its answer.

You need Docker Desktop, as set up in [M01-L03](../setup/m01-l03-setting-up-your-devops-lab/). Every lab runs in
containers on your own machine. Nothing else gets installed, and nothing touches the cloud.

| Sheet | Do it after | What it covers | Its files |
|---|---|---|---|
| [m02-linux.md](m02-linux.md): 30 Linux tasks on a broken server | Module 2 (Linux), [M02-L06](../linux/m02-l06-ssh-and-remote-servers/) | A broken Ubuntu 24.04 web server (systemd, nginx, an API, a small data disk, SSH). Shell and filesystem, users and permissions, processes and systemd, text processing, disks and memory, SSH | [m02-linux/](m02-linux/) |
| [m05-git.md](m05-git.md): Git rescue scenarios | Module 5 (Git), [M05-L04](../git/m05-l04-the-pull-request-workflow/) | Two "laptops" (Asha and Priya) and their remotes, with broken histories to rescue: commits on the wrong branch, lost commits and branches, merges and rebases gone wrong, a token in a commit, force-pushes, finding a bad commit, shipping a fix to a release | [m05-git/](m05-git/) |
| [m13-kubernetes.md](m13-kubernetes.md): 25 kubectl tasks on a broken cluster | Module 13 (Kubernetes), [M13-L06](../k8s/m13-l06-configmaps-and-secrets/) | A kind cluster (Kubernetes v1.37) running allcsvideos, broken on purpose: contexts, pods, Deployments, Services and DNS, ConfigMaps and Secrets | [m13-kubernetes/](m13-kubernetes/) |
| [m21-final.md](m21-final.md): 75 DevOps interview questions | Module 21, with [M21-L04 Full Mock Interview](../interview/m21-l04-full-mock-interview/) | The talking half of interview prep: concept, scenario, debug, design and behavioural questions over the whole course, with model answers | none, it's questions only |
| [m21-take-home.md](m21-take-home.md): 10 hands-on take-home tasks | Module 21, with [M21-L04 Full Mock Interview](../interview/m21-l04-full-mock-interview/) | The doing half: a Bash health check, a secure image, a Compose stack, a CI pipeline, a Terraform module, a Helm chart, SLO alerts, troubleshooting, supply-chain security, a design document | [m21-take-home/](m21-take-home/) |

## How to start each practice container

All commands are from the root of this repository. The sheets explain every flag, and end with clean-up commands.

**Module 2, the broken server web-01:**

```bash
cd practice/m02-linux
docker build --label course=devops -t m02lab-web01 .
docker run -d --name m02lab-web01 --label course=devops --hostname web-01 \
  --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock \
  --tmpfs /data:size=64m,nr_inodes=4096,mode=755 m02lab-web01
# wait about 30 seconds, then:
docker exec -it -u asha -w /home/asha m02lab-web01 bash -l
```

**Module 5, the Git rescue lab:**

```bash
cd practice/m05-git
docker build --label course=devops -t m05lab-lab .
docker run -d --name m05lab-lab --label course=devops --hostname lab m05lab-lab
docker exec -it -u asha -w /home/asha m05lab-lab bash -l      # Asha's laptop
docker exec -it -u priya -w /home/priya m05lab-lab bash -l    # Priya's laptop, in a second terminal
```

**Module 13, the broken cluster** (the tool box uses your Docker socket, so kind can create the node containers):

```bash
cd practice/m13-kubernetes
docker build --label course=devops -t m13lab-tools .
docker run -d --name m13lab-tools --label course=devops --hostname lab --network host \
  -v /var/run/docker.sock:/var/run/docker.sock m13lab-tools
docker exec -it m13lab-tools lab-up        # 2 to 4 minutes
docker exec -it m13lab-tools bash -l
```

**Module 21 take-home tasks:** each task has its own folder, `m21-take-home/tNN/`. The sheet says what to run in
each task. The tasks published on your machine use only `127.0.0.1`, ports 21051 to 21055.

## What's in the folders

```text
m02-linux/        Dockerfile (the broken server, it contains every answer), run-task.sh, tasks/NN.sh
m05-git/          Dockerfile (the rescue lab), run-task.sh, tasks/NN.sh
m13-kubernetes/   Dockerfile (the tool box with lab-up and lab-down), run-task.sh, tasks/NN.sh
m21-take-home/
  k8s-tools/      Dockerfile: docker CLI, kind v0.33.0, kubectl v1.37.1, Helm 4.3.1 (tasks 6 and 9)
  t01 .. t10/     starter/  the files the task gives you
                  solution/ the reference solution from the sheet (spoilers)
                  solution/staged/  broken copies the sheet uses to show that the checks catch mistakes
  t04/lab/        the local CI lab (Gitea and its runner) for task 4
  t08/troubleshooting-labs/  the Module 20 troubleshooting lab, already renamed to m21lab-tl and 10.0.205.0/24
```

The Dockerfiles are the same ones printed in each sheet, so you don't have to copy them out. They break things on
purpose, so they contain the answers. Build them without reading them.

**`run-task.sh` replays a reference answer** in your running lab: `./run-task.sh 05` (Module 5 also needs the
user: `./run-task.sh 03 asha`). It runs the commands from `tasks/05.sh` one by one and prints them with their
output. That's a spoiler, and it really applies the fix, so use it only after you've tried the task, or to compare
your output with the sheet's. Your PIDs, times and hashes will differ.

A few notes:
- Task 9 of the take-home: `make-repo.sh` is in `t09/starter/`. Generate your own cosign key pair as the sheet
  shows (`cosign generate-key-pair`). The reference run's keys are not included.
- Task 6 of the take-home: metrics-server v0.9.0 comes from its pinned release manifest,
  `https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml`.
- All passwords, keys and tokens in these labs are fake demo values, made only for these sandboxes.

## Next

When you've done both Module 21 sheets, run a full mock interview:
[M21-L04 · Full Mock Interview](../interview/m21-l04-full-mock-interview/).
