# M12-L03 · Mutable vs Immutable Infrastructure
> Video: Module 12, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- **Pets vs cattle**, and **mutable** (change servers in place) vs **immutable** (build a versioned image, replace instances) infrastructure
- Why mutable servers drift: a 2 a.m. hand fix leaves package and config differences that Ansible can't fully see, and a later release fails half-way
- The golden-image pipeline: **bake -> test -> scan -> tag/push -> deploy**, and **bake vs fry** (what goes into the image vs what is set at boot)
- **Packer** (HCL2): pinned plugins, a `docker` source, `shell` + `ansible` provisioners reusing the lesson 2 roles, `docker-tag` post-processor; `init`, `fmt`, `validate`, `build`
- Replace, never patch: deploy behind a load balancer by digest, see tampering with `docker diff`, roll back in seconds
- Trade-offs and where Ansible still fits (building images, stateful/legacy servers, network devices, one-off ops, orchestration)

## Before you start
- Docker Desktop with room for a few GB, and the Ansible lab from [M12-L01](../m12-l01-ansible-basics/) / roles from [M12-L02](../m12-l02-ansible-in-practice/) (this lesson's lab reuses M12-L01's images and setup scripts, so keep that folder next to this one).
- Concepts from Module 6/7 (images, Trivy) and Module 9 Lesson 2 (blue-green behind a load balancer).
- **Cost: free**, all local. The Packer licence note: since August 2023 HashiCorp products are BUSL-1.1 (building your own images is fine).

| Container | Hostname | Address | Role |
|---|---|---|---|
| `imm-control` | control | 10.0.123.10 | Ansible control node (asha) - the mutable world |
| `imm-web-01`, `imm-web-02` | web-01, web-02 | .11, .12 | long-lived web servers (systemd + OpenSSH) |
| `imm-build` | build-01 | .5 | image-build box: `hashicorp/packer:1.16.1` + docker CLI + ansible-core 2.21.5 |
| `imm-docker` | docker | .6 | the build box's own Docker engine (`docker:29.5.3-dind`): images, registry, test and "prod" instances live inside it |

## Files in this folder
| File | What it is |
|---|---|
| `mutable/v1/`, `mutable/v2/` | the fleet's Ansible repo, release 1 and release 2 (v2: nginx loads `conf.d` drop-ins, hc warns at 75% disk) |
| `golden/web.pkr.hcl` | the Packer template as first written (not yet formatted, no `groups`) |
| `golden/ansible/` | the lesson 2 roles with `image_build`, `image.yml` (the image playbook), `files/allcs-start` (start script: accepts `dev`, `staging`, `production`) |
| `golden/scripts/release.sh`, `deploy.sh`, `scan.sh` | bake+test+scan+push; replace instances behind the LB; Trivy `0.76.0` pinned by digest |
| `golden/lb/` | the nginx load balancer config and its (empty) upstream |
| `golden/pitfalls/leaky.pkr.hcl` | staged pitfall: a **fake** password baked into an image |
| `fixes/group_vars/web.yml`, `fixes/web.pkr.hcl` | the two later changes: `nginx_worker_connections: 1024`, and `groups = ["web"]` in the Ansible provisioner |
| `lab/up.sh`, `lab/down.sh`, `lab/images/build/`, `lab/setup-build.sh` | the lab |
| `lab/stage-release1.sh` | builds `~/allcs-ansible` from `mutable/v1` and applies release 1 |

## Follow along

### Part A - the mutable world
1. Start the lab (on your laptop, from this folder) and apply release 1 as Asha:
   ```bash
   bash lab/up.sh
   docker exec -it -u asha -w /home/asha imm-control bash -l
   ```
   ```bash
   eval "$(ssh-agent -s)"; ssh-add            # demo-passphrase-123 (fake)
   bash ~/m12-l03-mutable-vs-immutable-infrastructure/lab/stage-release1.sh
   cd ~/allcs-ansible
   ```

2. **2 a.m.**, staged on web-02's console (a second terminal on your laptop):
   ```bash
   docker exec imm-web-02 bash -c "apt-get upgrade -y && apt-get install -y htop strace \
     && sed -i 's/worker_connections 768/worker_connections 4096/' /etc/nginx/nginx.conf \
     && printf 'server {\n    listen 80 default_server;\n    location = /nginx_status { stub_status; }\n}\n' > /etc/nginx/conf.d/debug.conf \
     && nginx -t && systemctl reload nginx"
   ```

3. Next morning, on the control node:
   ```bash
   curl -s web-01/health; curl -s web-02/health
   diff <(ssh web-01 dpkg-query -W) <(ssh web-02 dpkg-query -W)
   ansible-playbook site.yml --check --diff --limit web-02
   ```
   Both healthy, but **5 package differences** (`htop`, `strace`, `libnl-3-200`, `libnl-genl-3-200` only on web-02, and a newer `liblzma5`). The dry run would put `worker_connections` back to 768 - and says nothing about packages (`state: present` doesn't check versions or extras).

4. Ship release 2:
   ```bash
   cp -r ~/m12-l03-mutable-vs-immutable-infrastructure/mutable/v2/. .
   git commit -qam "release 2: nginx drop-in configs, warn at 75% disk"; git log --oneline
   ansible-playbook site.yml
   ansible web -b -m shell -a "grep -E 'DISK_WARN|worker_conn|conf.d' /etc/hc/hc.conf /etc/nginx/nginx.conf"
   ```
   web-01: fine. web-02: `Render nginx.conf ... failed to validate` (the forgotten `debug.conf` is now loaded: duplicate default server). web-02 is now **half-configured**: `DISK_WARN=75` is live but nginx still has `worker_connections 4096` and no `conf.d` include - neither release 1 nor release 2.
   ```bash
   exit
   ```

### Part B - golden images (on the build box)
5. Open the build box and start the repository:
   ```bash
   docker exec -it -u asha -w /home/asha imm-build bash -l
   ```
   ```bash
   cp -r ~/m12-l03-mutable-vs-immutable-infrastructure/golden ~/golden && cd ~/golden
   git init -q && git add -A && git commit -qm "golden image: Packer template, web roles from release 2"
   packer version
   tree -L 2 --dirsfirst -I files
   cat web.pkr.hcl
   ```
   `Packer v1.16.1`.

6. Init, format, validate:
   ```bash
   packer init .
   packer fmt -check .; echo "exit $?"
   packer fmt -diff .
   git commit -qam "packer fmt"
   packer validate .
   packer validate -var version=1.0.0 .
   ```
   Plugins `docker 1.1.4` and `ansible 1.1.6` installed; `fmt -check` exits **3** (the `revision` variable's `=` signs aren't aligned) and `-diff` fixes it; `validate` without a version: `Unset variable "version"`; with it: `The configuration is valid.`

7. **Bake** version 1.0.0:
   ```bash
   time packer build -var version=1.0.0 -var revision=$(git rev-parse --short HEAD) .
   ```
   The shell step upgrades 3 packages already (`liblzma5 libsystemd0 libudev1` - a 2-week-old base image is already stale), Ansible runs the fleet's roles (starting nginx is skipped: `image_build`), and:
   ```
   Build 'docker.ubuntu' finished after 2 minutes 24 seconds.
   --> docker.ubuntu: Imported Docker image: allcs/web:1.0.0 with tags allcs/web:1.0.0
   ```

8. Inspect:
   ```bash
   docker images allcs/web
   docker image inspect allcs/web:1.0.0 -f '{{json .Config.Labels}}'
   docker image inspect allcs/web:1.0.0 -f '{{json .Config.Entrypoint}} {{json .Config.ExposedPorts}}'
   docker history allcs/web:1.0.0
   ```
   About 339 MB on disk, labels with version `1.0.0` and the git revision, entrypoint `/usr/local/bin/allcs-start`, one ~152 MB layer on top of Ubuntu.

9. **Test** - never ship an untested image:
   ```bash
   docker run -d --name web-test -e APP_ENV=staging -p 8080:80 allcs/web:1.0.0
   curl -s docker:8080/health
   curl -s docker:8080/
   docker exec web-test hc --dry-run
   docker rm -f web-test
   ```
   `{"status":"ok","host":"<id>","env":"staging","version":"1.0.0"}`, `<p>Golden image 1.0.0</p>`, and all five hc checks `OK` (storefront `HTTP 200 in 15 ms`).

10. **Scan** and **push**:
    ```bash
    scripts/scan.sh allcs/web:1.0.0; echo "exit $?"
    docker run -d --name registry -p 5000:5000 -v registry-data:/var/lib/registry registry:3.1.2 > /dev/null
    docker tag allcs/web:1.0.0 localhost:5000/allcs/web:1.0.0
    docker push localhost:5000/allcs/web:1.0.0
    ```
    Trivy: `Vulnerabilities 0`, `exit 0`.

11. **Deploy** behind a load balancer:
    ```bash
    docker network create prod > /dev/null
    docker create -q --name lb --network prod -p 8080:80 nginx:1.29.8-alpine
    docker cp -q lb/lb.conf lb:/etc/nginx/conf.d/default.conf
    docker cp -q lb/upstream.conf lb:/etc/nginx/upstream.conf
    docker start lb
    scripts/deploy.sh 1.0.0
    for i in 1 2 3 4; do curl -s docker:8080/health; done
    ```
    Two instances `web-1.0.0-1` / `web-1.0.0-2`, both healthy, requests alternate between them.

12. Identical? Then tamper on purpose:
    ```bash
    diff <(docker exec web-1.0.0-1 dpkg-query -W) <(docker exec web-1.0.0-2 dpkg-query -W) && echo identical
    docker inspect -f '{{.Name}} {{.Image}}' web-1.0.0-1 web-1.0.0-2
    docker exec web-1.0.0-2 sed -i 's/worker_connections 768/worker_connections 4096/' /etc/nginx/nginx.conf
    docker diff web-1.0.0-2
    ```
    `identical`, same image ID; `docker diff` shows `C /etc/nginx/nginx.conf` next to the runtime files: drift is visible at a glance.

13. The right way: the change goes into Git, then **release** and **deploy**:
    ```bash
    cp ~/m12-l03-mutable-vs-immutable-infrastructure/fixes/group_vars/web.yml ansible/group_vars/web.yml
    git diff
    git commit -qam "web: worker_connections 1024 (the 2 a.m. fix, reviewed)"
    time scripts/release.sh 1.0.1
    time scripts/deploy.sh 1.0.1
    for i in 1 2; do curl -s docker:8080/health; done
    docker exec web-1.0.1-2 grep worker_connections /etc/nginx/nginx.conf
    ```
    Release ~2m42s, deploy **2.3 s**; both old instances (including the tampered one) are gone. But the new instance still says `worker_connections 768`: Packer's inventory host `default` is in no group, so `group_vars/web.yml` never applied.

14. Fix the build (`groups = ["web"]`) and ship 1.0.2:
    ```bash
    cp ~/m12-l03-mutable-vs-immutable-infrastructure/fixes/web.pkr.hcl web.pkr.hcl
    git diff
    git commit -qam "packer: build host joins the web group"
    scripts/release.sh 1.0.2 && scripts/deploy.sh 1.0.2
    docker exec web-1.0.2-1 grep -E 'worker_conn|DISK_WARN' /etc/nginx/nginx.conf /etc/hc/hc.conf
    ```
    `worker_connections 1024;` and `DISK_WARN=75`.

15. **Rollback** and **bake vs fry**:
    ```bash
    curl -s docker:5000/v2/allcs/web/tags/list; echo
    time scripts/deploy.sh 1.0.1
    curl -s docker:8080/health
    scripts/deploy.sh 1.0.2
    docker image inspect allcs/web:1.0.2 -f '{{json .Config.Env}}'
    docker run -d --name web-staging -e APP_ENV=staging allcs/web:1.0.2 > /dev/null
    docker exec web-staging curl -s localhost/health
    docker exec web-1.0.2-1 curl -s localhost/health
    docker run --rm -e APP_ENV=prod allcs/web:1.0.2; echo "exit $?"
    docker rm -f web-staging
    ```
    Tags `1.0.0`, `1.0.1`, `1.0.2`; rollback in ~2.3 s; the image's env holds only `PATH`; the same image says `staging` or `production` depending on boot-time input; a typo fails fast: `allcs-start: unknown APP_ENV 'prod'`, `exit 64`.

16. **Pitfall: secrets baked into images** (fake value, staged):
    ```bash
    packer build pitfalls/
    docker run --rm --entrypoint cat allcs/web:leaky /etc/allcs.env
    docker images
    ```
    `DB_PASSWORD=demo-password-123` - anyone who can pull the image can read it. Inject secrets at boot instead. `docker images` also shows the size cost of every version (339 MB each here; `nginx` on Alpine is ~93 MB).

### For a cloud (not run here)
Swap the `docker` source for `amazon-ebs` (region, source AMI, instance type, SSH user, AMI name); the build block stays the same, and an Auto Scaling group launches instances from the new AMI ([M10-L04](../../cloud/m10-l04-compute/)). Building a real AMI starts a temporary EC2 instance (billed per second) and stores an EBS snapshot (billed per GB-month): deregister old AMIs and delete their snapshots (`aws ec2 deregister-image`, `aws ec2 delete-snapshot`) as part of image retention.

## Key ideas: trade-offs (numbers from this lab)
| | Mutable (Ansible in place) | Immutable (golden image) |
|---|---|---|
| Speed of change | seconds | a new image first (~2.5 min here) |
| Drift | yes (5 package differences after one night) | instances from one image are identical |
| Rollback | older playbook on an unknown state | deploy the previous image (2.3 s) |
| Testing | the playbook, against differing servers | the exact artifact you ship |
| Costs | snowflakes | build time, image sprawl (339 MB per version: retention rules) |
| State | can live on the server | must live outside (volumes, managed DBs, log systems) |

## Common mistakes
- Snowflake servers: never fix by hand without putting the fix in code.
- Stale golden images: rebuild on a schedule (e.g. weekly) and on every security fix, even if your code didn't change.
- Secrets baked into images: inject at boot from a secrets manager or the environment; scan images for secrets.
- Huge images: install only what the server needs.
- Logging into immutable servers and changing them: leave SSH out of the image, alert on drift (`docker diff`), let the next deploy replace them.

## Clean up
On your laptop, from this folder (removing `imm-docker` also removes every image, the registry and the instances built inside it):
```bash
bash lab/down.sh
```

## Next
[M12-B01 · Configure a VM Fleet with Ansible](../m12-b01-configure-a-vm-fleet-with-ansible/)
