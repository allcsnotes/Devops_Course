# M01-L03 · Setting Up Your DevOps Lab
> Video: Module 1, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- How Docker Desktop runs Linux containers on a Mac or Windows laptop (a small Linux VM, the engine/daemon, the client).
- The difference between an image and a container, and where images come from.
- The one command that starts your Ubuntu 24.04 practice server, piece by piece.
- How to set up Git and an SSH key for GitHub.
- Which VS Code extensions the course uses, and how the course repo is laid out.

## Before you start
- A laptop with macOS, Windows or Linux, and an internet connection.
- Windows: Docker's docs ask for WSL 2.1.5 or later, Windows 10 22H2 or Windows 11 23H2, 8 GB of RAM and virtualization turned on in the BIOS.
- No earlier lesson folder needed.

**The one rule for the whole course:** apart from Docker Desktop, VS Code and Git, nothing gets installed on your laptop. Every course tool runs inside a container, so everyone gets the same versions.

## Files in this folder
| File | What it is |
|---|---|
| `README.md` | This guide. Everything in this lesson is typed by hand. |

## How the pieces fit
| Piece | Think of it as | What it does |
|---|---|---|
| Docker Desktop | The power supply | Runs Linux containers on your laptop |
| Linux playground | Your practice server | A fresh Ubuntu 24.04 machine that starts in under a second, and that you may break |
| VS Code | Your workbench | Read and write scripts, Dockerfiles, YAML, Terraform |
| GitHub | Where the code lives | Hosts your repos, later runs your pipelines. You prove who you are with an SSH key |
| Course repo | The parts box | One folder per big topic, filled in as the course goes |

Containers need a Linux kernel, and macOS and Windows don't have one. So Docker Desktop starts a small Linux VM (on Windows usually on WSL 2). Inside it runs the Docker engine, a background service called the daemon, which pulls images and creates and starts containers. The `docker` command you type is only a client that talks to the engine's API. An image is a read-only template (like `ubuntu:24.04`); a container is one running copy of it. Images come from a registry (Docker Hub by default) and are cached after the first download. All containers share the VM's kernel, which is why they start in a fraction of a second.

## Follow along

### 1. Install and check Docker Desktop
Install Docker Desktop from docker.com (on a Mac, pick Apple silicon or Intel to match your chip). It is free for personal use, education, open source and small businesses (fewer than 250 employees and under 10 million dollars revenue); larger companies need a paid plan (Docker's docs, checked October 2026). Start it, then open a terminal:
```bash
docker --version
```
```
Docker version 29.5.3, build d1c06ef
```
```bash
docker version
```
You should see two sections, the client and the server (your versions and OS/Arch may differ):
```
Client:
 Version:           29.5.3
 OS/Arch:           darwin/arm64
 ...
Server: Docker Desktop 4.79.0 (230596)
 Engine:
  Version:          29.5.3
  OS/Arch:          linux/arm64
```
`darwin/arm64` means macOS on an Apple chip. The server runs on `linux/arm64` inside the VM. If Docker Desktop isn't running you get an error instead of a Server section: start it and try again.

### 2. The first test
```bash
docker run hello-world
```
```
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
...
Hello from Docker!
This message shows that your installation appears to be working correctly.

To generate this message, Docker took the following steps:
 1. The Docker client contacted the Docker daemon.
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (arm64v8)
 3. The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
 4. The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.
```
Run it a second time. The image is now cached, so it is almost instant (17 seconds the first time in the video, 0.19 seconds the second).

### 3. Start your Linux playground
This is the command you will use all course long:
```bash
docker run -it --rm --name devops-lab --hostname lab ubuntu:24.04 bash
```
| Piece | Meaning |
|---|---|
| `docker run` | Start a new container |
| `-it` | Interactive terminal, so you can type into it |
| `--rm` | Remove the container when you exit, so every session starts fresh |
| `--name devops-lab` | A name you can spot in `docker ps` |
| `--hostname lab` | The machine's name, shown in the prompt |
| `ubuntu:24.04` | The image: Ubuntu 24.04 LTS, pinned, never just `latest` |
| `bash` | The program to run inside: a shell |

You get a prompt like `root@lab:/#` (root, on host `lab`, in `/`, and `#` because you are root). Look around:
```bash
cat /etc/os-release
whoami
uname -m
```
```
PRETTY_NAME="Ubuntu 24.04.5 LTS"
...
VERSION="24.04.5 LTS (Noble Numbat)"
...
root
aarch64
```
`aarch64` is 64-bit ARM (Apple chip). On an Intel or AMD laptop you will see `x86_64`.

In a **second terminal on your laptop**:
```bash
docker ps
```
```
CONTAINER ID   IMAGE          COMMAND   CREATED         STATUS         PORTS     NAMES
bc55ba459acc   ubuntu:24.04   "bash"    5 seconds ago   Up 4 seconds             devops-lab
```

### 4. Git and an SSH key (inside the lab)
A fresh Ubuntu image doesn't even have Git. As root in the lab:
```bash
apt update
apt install -y git openssh-client
```
That installs 46 new packages (an 18.9 MB download, 95.9 MB on disk). Module 2 explains apt properly.

Real servers don't have you working as root, so create your own user and switch to it:
```bash
useradd -m -s /bin/bash asha
su - asha
```
`-m` makes a home folder, `-s` picks bash as the shell. The prompt changes to `asha@lab:~$` (`~` = home folder, `$` = normal user).
```bash
whoami
git --version
```
```
asha
git version 2.43.0
```
Tell Git who you are (use the email of your GitHub account; the video uses a fake one):
```bash
git config --global user.name "Asha"
git config --global user.email "asha@example.com"
git config --global init.defaultBranch main
git config --global --list
```
```
user.name=Asha
user.email=asha@example.com
init.defaultbranch=main
```
Sign up at github.com (a free account is enough). Then make an SSH key pair, with the command from GitHub's docs:
```bash
ssh-keygen -t ed25519 -C "asha@example.com"
```
Press Enter to accept the default file (`~/.ssh/id_ed25519`), then type a passphrase twice (nothing shows while you type, that is normal). It prints a fingerprint:
```
Your identification has been saved in /home/asha/.ssh/id_ed25519
Your public key has been saved in /home/asha/.ssh/id_ed25519.pub
The key fingerprint is:
SHA256:... asha@example.com
```
```bash
ls -l ~/.ssh
cat ~/.ssh/id_ed25519.pub
```
```
-rw------- 1 asha asha 464 ... id_ed25519
-rw-r--r-- 1 asha asha  98 ... id_ed25519.pub
ssh-ed25519 AAAA...  asha@example.com
```
- `id_ed25519` is the **private** key. Only you can read it. Never share it.
- `id_ed25519.pub` is the **public** key: one line with the key type, the key, and your email as a comment. This is the one GitHub needs.

Add it on GitHub: profile picture, **Settings**, **SSH and GPG keys** (Access section), **New SSH key**. Give it a title, keep the type as **Authentication**, paste the public key, click **Add SSH key**. Then test:
```bash
ssh -T git@github.com
```
GitHub's docs say it replies: `Hi <your-username>! You've successfully authenticated, but GitHub does not provide shell access.`

> The lab is wiped when you exit. Make your **real** key on your own laptop, where it stays. It is the same `ssh-keygen` command on a Mac, on Linux, or in Git Bash on Windows.

Type `exit` twice to leave asha's shell and the lab.

### 5. VS Code and five extensions
Install Visual Studio Code from code.visualstudio.com (free on Mac, Windows and Linux). Open the Extensions view and search for each by name:

| Extension | Publisher | Why |
|---|---|---|
| Container Tools | Microsoft | Browse images and containers, help writing Dockerfiles. Replaces the old "Docker" extension |
| YAML | Red Hat | Checks YAML as you type (pipelines, Compose, Kubernetes) |
| HashiCorp Terraform | HashiCorp | Highlighting and completion for Terraform |
| Kubernetes | Microsoft | Browse clusters and manifests (module 13 on) |
| Dev Containers | Microsoft | Open any folder inside a container, in the same Linux as your lab |

### 6. Clone the course repo
Clone it once, on your laptop (this is the link from the resources below the video):
```bash
git clone https://github.com/allcsnotes/Devops_Course.git
cd Devops_Course
```
The folders the video walks through:
```
Devops_Course/
├── linux/           module 2   Linux practice
├── scripts/         module 3   shell and Python automation
├── docker/          modules 6-7   Dockerfiles and Compose
├── ci/              modules 8-9   pipelines
├── terraform/       modules 10-11   AWS infrastructure
├── k8s/             modules 13-15   Kubernetes
└── observability/   modules 16-17   dashboards and alerts
```
The repo also has a folder for the other modules (`setup/` for module 1, `networking/`, `git/`, `cloud/`, `ansible/`, `security/`, `platform/`, `capstones/`, `interview/`) and `allcsvideos/`, the app the course deploys. Each lesson has its own folder with a README like this one; the top-level README lists them all.

## Common mistakes
1. **Chip architecture.** An Apple-silicon Mac runs arm64 images. Most official images ship arm64 and amd64, and Docker picks yours. You can force the other one:
   ```bash
   docker run --rm ubuntu:24.04 uname -m
   docker run --rm --platform linux/amd64 ubuntu:24.04 uname -m
   ```
   ```
   aarch64
   ...
   x86_64
   ```
   The second one is emulated: it works but is slower. Use it only when an image has no arm64 build.
2. **Memory.** Docker Desktop's VM gets a fixed slice of your RAM, by default half. Check it:
   ```bash
   docker info | grep -E 'CPUs|Total Memory'
   ```
   ```
    CPUs: 10
    Total Memory: 7.75GiB
   ```
   (That is a 16 GB Mac.) Change it in Docker Desktop **Settings, Resources, Advanced**, with the CPU limit and swap (1 GB by default). When later modules run a Kubernetes cluster and containers start dying, look here first.
3. **Windows.** Use the WSL 2 backend and keep your course files inside the Linux file system. Docker's docs warn that folders mounted from the Windows side (under `/mnt/c`) are slower.
4. **The lab forgets.** Prove it:
   ```bash
   docker run --rm --name notes-test --hostname lab ubuntu:24.04 bash -c 'touch /root/notes.txt; ls /root'
   docker ps -a --filter name=notes-test
   ```
   The first prints `notes.txt`; the second finds nothing. `--rm` deleted the container and the file with it. Keep real work in the course repo, never only inside the lab.
5. **The private key.** Never paste `id_ed25519` (the file without `.pub`) anywhere: not into GitHub, not into a chat, not into a repo. Only the `.pub` file leaves your laptop.

**Interview warm-up: what happens when you run `docker run hello-world`?** The docker client sends the request to the Docker daemon, which pulls the image from a registry if it isn't cached, creates a container from it, starts it, and streams its output back to the client.

## Clean up
Lab containers started with `--rm` remove themselves when you exit. Optionally remove the images this lesson pulled (you will need `ubuntu:24.04` again in Module 2, so keeping it is fine):
```bash
docker rmi hello-world
```
Keep your real SSH key and the cloned repo.

## Next
[M01-L04 · From Laptop to Production](../m01-l04-from-laptop-to-production/)
