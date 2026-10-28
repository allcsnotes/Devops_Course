# M12-B01 · Configure a VM Fleet with Ansible
> Video: Module 12, Build 1. Watch it first, then follow along here.

## What you'll learn
- Taking five **bare** Ubuntu 24.04 servers (one load balancer, four web servers) to a **hardened, load-balanced fleet** with one `site.yml` and six small roles: `common`, `hardening`, `nginx`, `app`, `lb`, `hc_toolkit`
- Safety nets that stop bad changes before they land: `visudo -cf`, `sshd -t`, `nginx -t` via `validate`, and a **lockout guard**
- A firewall plan with ufw: SSH only from the bastion, port 80 on web servers only from the load balancer
- Secrets in Ansible Vault, the release version pinned in `group_vars`, and idempotency (`changed=0`)
- **Zero-downtime rolling updates** with `rolling.yml`: `serial: 25%`, `max_fail_percentage: 0`, drain from the LB, update, health-check, put back
- A staged bad release that stops after one server, rollback with `git revert`, and adding web-05 in minutes

## Before you start
- Docker Desktop (the servers pull packages from Ubuntu mirrors and PyPI, so you need internet), and the M12-L01 lab folder next to this one ([M12-L01](../m12-l01-ansible-basics/): its images are reused).
- Lessons [M12-L01](../m12-l01-ansible-basics/) and [M12-L02](../m12-l02-ansible-in-practice/) (roles, templates, handlers, vault), ufw from Module 4, SSH hardening and the bastion from Module 2, the hc toolkit from Module 3.
- **Cost: free**, all local. Fake values only: SSH key passphrase `demo-passphrase-123`, vault password `demo-vault-pass-123`, webhook token `demo-token-123`. Rahul's public key is a demo key whose private half was deleted.

| Container | Host | Address | Role |
|---|---|---|---|
| `fleet-control` | control | 10.0.126.10 | Ansible control node **and the bastion** |
| `fleet-lb-01` | lb-01 | 10.0.126.5 | nginx load balancer |
| `fleet-web-01` ... `fleet-web-04` | web-01..04 | .11-.14 | web servers (nginx -> Course Copilot on 127.0.0.1:8000) |
| `fleet-web-05` | web-05 | .15 | added at the end with `lab/addnode.sh` |

## Files in this folder
| File | What it is |
|---|---|
| `final/` | the finished repository `allcs-fleet`: `site.yml`, `rolling.yml`, `tasks/lb-member.yml`, six roles, `group_vars` (`all/vault.yml` **encrypted** with the fake `demo-vault-pass-123`), `requirements.yml` (`ansible.posix 2.2.2`, `community.general 13.5.0`), its own README with all the measured numbers |
| `stages/inventory.s1.ini` | the inventory before web-05 |
| `stages/site.s1.yml` ... `site.s4.yml`, `stages/web.s1.yml` | `site.yml` as it grows step by step; `group_vars/web.yml` pinned to `1.8.0` |
| `stages/vault.plain.yml` | the (fake) webhook secret before encryption |
| `stages/broken/10-hardening.conf.j2` | staged typo: `AllowGroup` instead of `AllowGroups` |
| `stages/scale/prod.aws_ec2.yml` | example dynamic inventory (amazon.aws `aws_ec2`) - not run, there is no AWS here |
| `release/make-release.sh`, `release/src/1.8.0`, `1.9.0`, `1.9.1` | Course Copilot release sources and the tarball builder (`1.9.1` is a **staged bad build**: `catalog.json` instead of `courses.json`) |
| `traffic/users.sh`, `traffic/traffic.py` | simulated users: 40 requests/s to lb-01, results per request/second in `traffic/runs/` |
| `lab/up.sh`, `lab/addnode.sh`, `lab/down.sh`, `lab/setup-node.sh` | the lab (servers start **bare**) |

## Follow along
`$L` is this lesson folder on the control node (`~/m12-b01-configure-a-vm-fleet-with-ansible`). Commands after step 1 run as asha in `~/allcs-fleet` unless they say "on your laptop".

1. Start the lab (on your laptop, from this folder) and open a shell as Asha:
   ```bash
   bash lab/up.sh
   docker exec -it -u asha -w /home/asha fleet-control bash -l
   ```

2. The project skeleton, as a git repo:
   ```bash
   L=~/m12-b01-configure-a-vm-fleet-with-ansible
   eval "$(ssh-agent -s)" && ssh-add          # demo-passphrase-123 (fake)
   mkdir -p ~/allcs-fleet/group_vars/all && cd ~/allcs-fleet
   cp $L/final/{ansible.cfg,requirements.yml,.gitignore} . && cp $L/stages/inventory.s1.ini inventory.ini
   cp $L/final/group_vars/all/vars.yml group_vars/all/vars.yml
   sed -i "s|key: ssh-ed25519 .* asha@example.com|key: $(cat ~/.ssh/id_ed25519.pub)|" group_vars/all/vars.yml
   git init -q && git add -A && git commit -qm "fleet skeleton"
   ```
   **Important:** the `sed` puts *your* lab key in `admin_users`. The `common` role sets authorized keys **exclusively**; with the video's key you would lock yourself out.
   ```bash
   tree -a -I .git
   (umask 077; echo 'demo-vault-pass-123' > ~/.vault-pass.txt)
   ls -l ~/.vault-pass.txt
   ansible-inventory --graph
   ansible-galaxy collection install -r requirements.yml
   ssh-keyscan -t ed25519 10.0.126.5 10.0.126.11 10.0.126.12 10.0.126.13 10.0.126.14 2>/dev/null >> ~/.ssh/known_hosts
   ansible all -m ping
   ```
   (`ssh-keyscan` without checking is a lab shortcut; compare fingerprints as in M12-L01 for real servers.) Five `pong`s.

3. How bare are they?
   ```bash
   ansible all -b -m shell -a "sshd -T | grep -E '^(permitrootlogin|passwordauthentication) '"
   ansible all -m shell -a 'command -v ufw nginx || echo none'
   ```
   `permitrootlogin without-password`, `passwordauthentication yes`, and `none`.

4. **common** - the baseline (base packages, UTC, timesyncd, unattended upgrades, admins + exclusive keys + sudo checked by `visudo`):
   ```bash
   mkdir -p roles && cp -r $L/final/roles/common roles/
   cp $L/stages/site.s1.yml site.yml
   ansible-playbook site.yml
   git add -A && git commit -qm "common role"
   ansible all -m command -a "id rahul"
   ansible web-01 -m command -a "timedatectl show -p Timezone"
   ansible web-01 -m shell -a "grep ^ConditionVirt /usr/lib/systemd/system/systemd-timesyncd.service; systemctl show systemd-timesyncd -p ConditionResult"
   ansible web-01 -m command -a "apt-config dump APT::Periodic::Unattended-Upgrade"
   ```
   9 changes per server (~1 min). Rahul exists in `admins` and `sshusers`; time zone `UTC`; timesyncd is skipped in a container (`ConditionVirtualization=!container`) but runs on a real VM.

5. **hardening** - guard, sshd drop-in (`validate: sshd -t`), ufw in the safe order:
   ```bash
   cp -r $L/final/roles/hardening roles/ && cp $L/stages/site.s2.yml site.yml
   ansible-playbook site.yml
   git add -A && git commit -qm "hardening role"
   ansible all -b -m shell -a "sshd -T | grep -E '^(permitrootlogin|passwordauthentication|allowgroups) '"
   ssh -o PubkeyAuthentication=no 10.0.126.11
   ansible web-01 -b -m command -a "ufw status verbose"
   ```
   5 changes per server; `permitrootlogin no`, `passwordauthentication no`, `allowgroups sshusers`; the password-only login gets `Permission denied (publickey)`; ufw `active`, default deny incoming, `22/tcp ALLOW IN 10.0.126.10`.

6. **nginx + app** - build release 1.8.0 and deploy it:
   ```bash
   ls ~/copilot-src
   ~/make-release.sh 1.8.0
   tar -tzf ~/releases/copilot-1.8.0.tar.gz
   cp -r $L/final/roles/nginx $L/final/roles/app roles/ && cp $L/stages/web.s1.yml group_vars/web.yml && cp $L/stages/site.s3.yml site.yml
   ansible-playbook site.yml
   git add -A && git commit -qm "nginx + app roles, Course Copilot 1.8.0"
   ansible web -m command -a "curl -s localhost/health"
   ansible web-01 -m command -a "systemctl status copilot --no-pager -n 0"
   ansible web-01 -b -m command -a "ufw status"
   ```
   17 changes per web server; each answers `status ok`, version `1.8.0`, 5 courses; `copilot` is active; ufw allows port 80 from `10.0.126.5` only.

7. **lb** - the load balancer, its pool generated from the inventory:
   ```bash
   cp -r $L/final/roles/lb roles/ && cp $L/final/group_vars/lb.yml group_vars/ && cp $L/stages/site.s4.yml site.yml
   ansible-playbook site.yml
   git add -A && git commit -qm "lb role"
   ansible lb-01 -m command -a "grep server /etc/nginx/conf.d/lb.conf"
   for i in 1 2 3 4 5 6; do curl -s lb-01/health; echo; done
   curl -sS -m 3 web-01/health
   ```
   6 changes on lb-01; four `server` lines; requests rotate web-01 -> 02 -> 03 -> 04 -> 01; `web-01` directly: **timed out** (only the LB gets in).

8. **Secrets and monitoring**:
   ```bash
   cp $L/stages/vault.plain.yml group_vars/all/vault.yml
   cat group_vars/all/vault.yml
   ansible-vault encrypt group_vars/all/vault.yml
   head -3 group_vars/all/vault.yml
   grep -n vault group_vars/all/vars.yml ansible.cfg
   cp -r $L/final/roles/hc_toolkit roles/ && cp $L/final/site.yml site.yml
   ansible-playbook site.yml
   git add -A && git commit -qm "vault + hc toolkit"
   ansible web-01 -b -m shell -a 'systemctl start hc; journalctl -u hc -o cat --no-pager | tail -8'
   ansible lb-01 -b -a "ls -l /etc/hc/hc.conf"
   ansible-playbook site.yml
   ```
   `$ANSIBLE_VAULT;1.1;AES256`; 8 changes per server; hc checks memory, load, 3 services and Copilot (`HTTP 200`); `hc.conf` is readable only by root and the `hc` group; the last full run: **`changed=0` on all five** (~2 min).

9. **Rolling release 1.9.0 under load**:
   ```bash
   cp $L/final/rolling.yml . && mkdir -p tasks && cp $L/final/tasks/lb-member.yml tasks/
   git add -A && git commit -qm "rolling.yml"
   ~/make-release.sh 1.9.0
   sed -i 's/"1.8.0"/"1.9.0"/' group_vars/web.yml
   git diff
   git commit -qam "Release Course Copilot 1.9.0"
   ```
   On your laptop, start the users (from this folder):
   ```bash
   bash traffic/users.sh rolling 900
   ```
   Back on the control node:
   ```bash
   ansible-playbook rolling.yml
   ansible-playbook rolling.yml
   ```
   One server per batch: marked `down` on lb-01, updated, health-checked from the LB, marked `up`. Then on your laptop: `docker stop -t 30 fleet-users; tail -3 traffic/runs/rolling.txt`. In the video: 2 min 14 s, **6,103 requests, 0 failed**. The second run: `changed=0`, nobody leaves the pool.

10. **A bad release** (staged: 1.9.1 renamed the course index):
    ```bash
    ~/make-release.sh 1.9.1
    sed -i 's/"1.9.0"/"1.9.1"/' group_vars/web.yml
    git commit -qam "Release Course Copilot 1.9.1"
    git log --oneline -3
    ```
    Laptop: `bash traffic/users.sh bad 1200`. Control node:
    ```bash
    ansible-playbook rolling.yml
    ansible web-01 -m command -a "curl -s localhost:8000/health"
    ansible lb-01 -m command -a "grep 10.0.126.1 /etc/nginx/conf.d/lb.conf"
    tar -tzf ~/releases/copilot-1.9.1.tar.gz | grep data
    ```
    web-01's health check returns 503 for 15 tries, then `NO MORE HOSTS LEFT`: the rollout stops after **one** server; web-02..04 untouched; web-01 reports `degraded`, stays marked `down` on the LB; the tarball has `data/catalog.json`, not `courses.json`. Users saw nothing (video: 5,572 requests, 0 failed). Roll back:
    ```bash
    git revert --no-edit HEAD
    ansible-playbook rolling.yml
    ```
    Only web-01 changes (5 changes), back on 1.9.0 and back in the pool. Laptop: `docker stop -t 30 fleet-users`.

11. **A typo in the sshd template** (staged):
    ```bash
    cp $L/stages/broken/10-hardening.conf.j2 roles/hardening/templates/10-hardening.conf.j2
    git diff --stat; git diff -U0 | tail -2
    ansible-playbook site.yml --tags hardening
    ansible web-01 -b -m command -a "grep Allow /etc/ssh/sshd_config.d/10-hardening.conf"
    ansible all -m ping | grep -c pong
    git checkout roles/hardening/templates/10-hardening.conf.j2; git status --short
    ```
    `validate` fails on all five (`line 5: Bad configuration option: AllowGroup`), the file is never replaced, SSH never restarts, all `5` still answer.

12. **The lockout guard** (a logic mistake `sshd -t` can't catch):
    ```bash
    ansible-playbook site.yml --tags hardening -l web-01 -e '{"hardening_ssh_allow_groups": ["ssh-users"]}'
    ```
    The guard refuses: asha is in none of the allowed groups, *refusing to lock us out*.

13. **web-05, bare to serving** (on your laptop first):
    ```bash
    bash lab/addnode.sh web-05 15
    bash traffic/users.sh grow 1200
    ```
    Control node:
    ```bash
    sed -i '/^web-04/a web-05 ansible_host=10.0.126.15' inventory.ini
    git diff
    ssh-keyscan -t ed25519 10.0.126.15 2>/dev/null >> ~/.ssh/known_hosts
    git commit -qam "Add web-05"
    ansible-playbook site.yml --limit web-05,lb
    for i in 1 2 3 4 5; do curl -s lb-01/health; echo; done
    ```
    web-05 `changed=39`, lb-01 `changed=2` (one upstream line + reload), ~3 min 19 s with traffic running (video: 8,885 requests, 0 failed); lb-01 now rotates through five servers. Laptop: `docker stop -t 30 fleet-users`.

At the end, `diff -r -x .git ~/allcs-fleet $L/final` should show only the README and your own asha key line.

### At real scale (not run here)
- Inventory from the cloud: the `amazon.aws.aws_ec2` plugin builds groups from tags (`Role=web` -> group `web`) - see `stages/scale/prod.aws_ec2.yml`. On real EC2 instances the servers bill per hour: terminate what you don't use.
- Run playbooks from AWX / Ansible Automation Platform (schedules, RBAC, credentials, run history).
- Bake the same roles into golden images with Packer ([M12-L03](../m12-l03-mutable-vs-immutable-infrastructure/)); Kubernetes Deployments do rolling updates themselves (Module 13).
- Extensions: Molecule tests per role, ansible-lint and a check-mode diff on every PR, TLS on the LB, a canary batch of one.

## Common mistakes
- Exclusive authorized keys with the wrong key list: you lock yourself out (step 2).
- Trusting `sshd -t` alone: it checks syntax, not who can still log in - add a guard.
- Opening the firewall before allowing SSH from the bastion: allow 22 first, then deny everything else.
- Running `site.yml` in the middle of a rollout: its template resets every server to "up" in `lb.conf`.
- A rollout that keeps going after a failure: `serial` + `max_fail_percentage: 0` + a real health check from the load balancer.

## Clean up
On your laptop, from this folder (removes all `fleet-*` containers including web-05 and the traffic generator):
```bash
bash lab/down.sh
rm -rf traffic/runs
```

## Next
[M13-L01 · Why Orchestration](../../k8s/m13-l01-why-orchestration/)
