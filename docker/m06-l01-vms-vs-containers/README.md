# M06-L01 · VMs vs Containers
> Video: Module 6, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- Why "it works on my machine" happens, and how packaging an app with its runtime fixes it
- The three ways to keep apps apart: physical servers, virtual machines (type 1 and type 2 hypervisors), containers
- What a container really is: an ordinary Linux process + **namespaces** (what it sees) + **cgroups** (what it uses) + its own **root filesystem** (from the image)
- How to prove every piece by hand: the eight namespace types, `unshare`, `chroot`, cgroup limits and an OOM kill
- The chain behind `docker run`: docker CLI -> dockerd -> containerd -> shim -> runc, built on the OCI standards
- Why a container is a thinner wall than a VM, and the four classic mistakes

## Before you start
- Docker Desktop (the video used 4.79, engine 29.5.3) on macOS or Windows, or Docker Engine on Linux.
- A terminal. On Windows, use **Git Bash or a WSL shell** for this lesson (one step pipes a tar stream between two commands).
- Images used, all pinned: `python:3.12.15-slim`, `nginx:1.29.8-alpine`, `ubuntu:24.04`, `ubuntu:22.04`.
- No earlier lesson folder is needed. Background that helps: M01-L03 (Docker Desktop runs a Linux VM), M02-L05 (memory and the OOM killer), M04 (Linux networking, veth pairs).

In the video every container name starts with a course prefix (`do-m06l01-web`). Here the names are short: `web`, `limited`, `hog`, `oom`, `lab`.

## Files in this folder
| File | What it is |
|---|---|
| `copilot_check.py` | Course Copilot's startup check. Uses a `type` statement, which only exists since Python 3.12 |
| `oldserver/Dockerfile` | Image `m06-oldserver`: Ubuntu 22.04 with Python 3.10, plays the old server `web-01` |
| `lab/Dockerfile` | Image `m06-lab`: Ubuntu 24.04 with `unshare`, `lsns`, `nsenter`, `ps`, `ip`, `pstree`, Python 3.12, users `asha` and `priya` |

## Follow along
Run everything from this folder.

### 1. The problem: same code, different machine (optional replay)
The video showed this on two machines. You can replay it with two small images:
```bash
docker build -t m06-lab lab
docker build -t m06-oldserver oldserver

# "dev box": Ubuntu 24.04, Python 3.12
docker run --rm -v "$PWD":/app -w /app m06-lab python3 copilot_check.py
# "web-01": Ubuntu 22.04, Python 3.10
docker run --rm -v "$PWD":/app -w /app m06-oldserver python3 --version
docker run --rm -v "$PWD":/app -w /app m06-oldserver python3 copilot_check.py
```
You should see the dev box print `Course Copilot ready. Top course: dsa`, and the old server print `Python 3.10.12` and then:
```
    type Score = float      # new in Python 3.12
         ^^^^^
SyntaxError: invalid syntax
```

### 2. The fix: ship the runtime with the code
```bash
docker run --rm -v "$PWD":/app -w /app python:3.12.15-slim python copilot_check.py
```
```
Course Copilot ready. Top course: dsa
```
The image carries Python. The machine only needs Docker.

### 3. A container is just a process
Start nginx in the background:
```bash
docker run -d --name web nginx:1.29.8-alpine
```
Docker prints the new container's ID. Look inside:
```bash
docker exec web ps
```
```
PID   USER     TIME  COMMAND
    1 root      0:00 nginx: master process nginx -g daemon off;
   30 nginx     0:00 nginx: worker process
   ...
   40 root      0:00 ps
```
Inside, nginx is PID 1 (one worker per CPU, so your count may differ). Now from the outside:
```bash
docker top web -o pid,ppid,user,args
docker inspect -f '{{.State.Pid}}' web
```
Out here the master has a big PID (86472 in the video) and a parent (the containerd shim). `docker inspect` gives the same PID. Write it down, you need it in step 5.

### 4. One kernel, shared
```bash
docker exec web uname -r
docker info --format '{{.KernelVersion}} on {{.OperatingSystem}}'
```
```
6.12.76-linuxkit
6.12.76-linuxkit on Docker Desktop
```
Same kernel inside and out. (Your version will differ; on Linux you see your host's kernel.)

### 5. The VM's side of the story (lab trick)
Open a lab shell that shares the Docker host's process list, hostname and cgroups. **This is a debugging trick for a lab, never for production.**
```bash
docker run -it --rm --privileged --pid=host --uts=host --cgroupns=host m06-lab bash
```
The prompt says `root@docker-desktop` (on Linux: your machine's hostname). Inside it, set `P` to the PID from step 3 and look around:
```bash
P=86472          # use YOUR number from: docker inspect -f '{{.State.Pid}}' web
uname -r
ps -C nginx -o pid,ppid,user,cmd
pstree -p -s $P | head -1
ps -o pid,ppid,cmd -C dockerd,containerd
```
You should see something like:
```
initd(1)---containerd-shim(86449)---nginx(86472)-+-nginx(86510)
```
No VM in sight, just a branch of the process tree. The workers show as user `101` here, `statd` in `docker top`, and `nginx` inside: all are user ID 101, names come from each filesystem's own passwd file.

Now the namespaces, with evidence (still in the lab shell):
```bash
lsns -p $P
readlink /proc/1/ns/pid /proc/$P/ns/pid
nsenter -t $P -n ip -br addr show eth0
nsenter -t $P -u hostname
cat /proc/$P/cgroup
nsenter -t 1 -m grep PRETTY /etc/os-release
head -2 /etc/os-release
exit
```
`lsns` lists 7 namespaces of nginx's own (mnt, uts, ipc, pid, cgroup, net, time); the **user** namespace is shared with PID 1. The two `readlink` lines show two different PID namespace IDs. The VM's filesystem says `Docker Desktop`, the lab shell says `Ubuntu 24.04`: three filesystems, one kernel.

Compare with the view from inside the container:
```bash
docker exec web hostname
docker exec web head -2 /etc/os-release
docker exec web ip addr show eth0
docker exec web cat /proc/self/uid_map
docker exec web cat /proc/self/cgroup
```
```
ffd2c1d597dc                      <- short container ID = hostname (UTS)
NAME="Alpine Linux"               <- its own files (mount)
11: eth0@if74: ... inet 172.17.0.5/16 ...   <- its own network, a veth pair
         0          0 4294967295  <- identity map: root inside is root outside
0::/                              <- it sees its own cgroup as the whole tree
```

### 6. Build a container by hand with `unshare`
Start a privileged lab container and copy the nginx container's files into it:
```bash
docker run -d --privileged --hostname lab --name lab m06-lab
docker exec lab mkdir /srv/rootfs
docker export web | docker exec -i lab tar -x -C /srv/rootfs
```
Open a shell in it (terminal 1):
```bash
docker exec -it lab bash
```
Inside:
```bash
cd ~
hostname
ps -e
unshare --pid --fork --mount-proc --uts --net bash
echo $$
ps -ef
hostname box1
hostname
ip -br link
```
`echo $$` prints `1`, `ps -ef` shows just two processes, the hostname changes only in here, and `ip -br link` shows `lo` (DOWN) plus a few tunnel devices, no `eth0`.

In a **second terminal**, look from outside:
```bash
docker exec -it lab bash
hostname
ps -e -o pid,ppid,cmd --forest
exit
```
Still `lab`, and `unshare` plus its `bash` have ordinary PIDs (105 and 106 in the video).

Back in terminal 1, give it its own files:
```bash
chroot /srv/rootfs /bin/sh
mount -t proc proc /proc
head -2 /etc/os-release
ps
exit
exit
hostname
```
`os-release` says Alpine Linux, `ps` shows bash as PID 1. After the two `exit`s, `hostname` says `lab` again: when the last process leaves, the namespaces disappear. That's a container. runc does the same with more care (pivot_root, cgroups, dropped capabilities, seccomp).

Now the user namespace, as a normal user:
```bash
exit                       # leave the root shell
docker exec -it -u asha lab bash
id -u
unshare --user --map-root-user bash
whoami
cat /proc/self/uid_map
exit
exit
```
```
1000
root
         0       1000          1
```
Root in here is user 1000 outside. That's how rootless containers work.

### 7. Cgroups: what a process may use
```bash
docker run -d --name limited --memory 100m --cpus 0.5 nginx:1.29.8-alpine
docker exec limited cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max
docker exec web cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max
```
```
104857600
50000 100000
max
max 100000
```
`limited` gets 100 MiB and half a CPU; `web` (no flags) has no limits at all, Docker's default.

A noisy neighbour, staged on purpose:
```bash
docker run -d --name hog --cpus 0.5 ubuntu:24.04 sh -c 'while :; do :; done'
docker stats --no-stream web limited hog
```
```
NAME      CPU %     MEM USAGE / LIMIT    MEM %
web       0.00%     8.719MiB / 7.75GiB   0.11%
limited   0.00%     8.598MiB / 100MiB    8.60%
hog       49.70%    588KiB / 7.75GiB     0.01%
```
The hog is held at half a core. `web`'s limit is the whole VM.

Hit a memory limit, staged on purpose:
```bash
docker run --name oom --memory 100m --memory-swap 100m ubuntu:24.04 tail /dev/zero
echo $?
docker inspect -f '{{.State.OOMKilled}} {{.State.ExitCode}}' oom
```
```
137
true 137
```
137 = 128 + 9 (SIGKILL). Only this container died.

### 8. Who set this up?
```bash
docker version
docker info --format '{{.DefaultRuntime}} {{.Driver}} cgroup-v{{.CgroupVersion}}'
```
Look for the server parts: Engine 29.5.3, containerd v2.2.5, runc 1.3.6, docker-init 0.19.0, and `runc overlayfs cgroup-v2`.

Startup time, and a teaser for the next lesson:
```bash
time docker run --rm ubuntu:24.04 true
docker exec web df -h /
docker images nginx:1.29.8-alpine
docker image inspect -f '{{len .RootFS.Layers}}' nginx:1.29.8-alpine
```
The video measured `real 0m0.259s`, a root filesystem of type `overlay`, 26.7 MB content size / 92.7 MB disk usage, and `8` layers.

### 9. Pitfall check: who are you inside?
```bash
docker exec web whoami
```
```
root
```

## Common mistakes
1. **Treating a container like a VM**: an SSH server inside, many processes, patching by hand. Run one main process, debug with `docker exec`, and replace the container instead of repairing it.
2. **Running as root**: `whoami` says `root`, and with no user namespace that is root on the shared kernel. Module 7 sets a non-root user.
3. **Assuming isolation means security**: one kernel is shared by every container. Never use `--privileged` in production (we used it only in this lab) and never hand a container the Docker socket.
4. **No resource limits**: by default a container may use the whole machine (7.75 GiB in the video). Set `--memory` and `--cpus`. Kubernetes calls them requests and limits (module 14).

## Key ideas
| | Virtual machine | Container |
|---|---|---|
| Isolates | Hardware (hypervisor) | Processes (namespaces + cgroups) |
| Kernel | Its own guest kernel | Shares the host kernel |
| Size / start | Whole OS (Ubuntu 24.04 cloud image: 588 MB) | nginx image 26.7 MB download, starts in ~0.26 s |
| Wall | Thick | Thinner |

- Type 1 hypervisors run on the hardware (VMware ESXi, Hyper-V, KVM); type 2 run as an app (VirtualBox, Parallels).
- The 8 namespaces: PID, mount, network, UTS, IPC, user, cgroup, time. There is no "container" object in the kernel.
- OCI (2015, Linux Foundation): image spec, runtime spec (runc is the reference), distribution spec. That's why images run on Docker, Podman or Kubernetes.
- Thicker walls when you need them: gVisor (user-space kernel), Kata Containers (lightweight VM per container), Firecracker microVMs (AWS Lambda, Fargate).

## Clean up
```bash
docker rm -f web limited hog oom lab
docker rmi m06-lab m06-oldserver
```

## Next
[M06-L02 · Images, Layers and Registries](../m06-l02-images-layers-and-registries/)
