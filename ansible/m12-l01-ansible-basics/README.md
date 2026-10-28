# M12-L01 · Ansible Basics
> Video: Module 12, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- Configuration management: declare the **desired state** once, let a tool make every server match it (and fix **drift** and **snowflake servers**)
- How Ansible works: **push, agentless**, over SSH, Python on the target; ok / changed / failed; forks; vs Puppet, Chef, Salt
- Installing ansible-core in a venv, the **inventory** (INI and YAML), `group_vars`, `ansible.cfg`, and verifying **host keys** properly
- Ad-hoc commands (`command`, `shell`, `apt`, `service`, `copy`, `user`, `setup`), `become`, `--limit`, forks
- Your first **playbook**: FQCNs, `--syntax-check`, `--list-hosts`, `--check --diff`, and **idempotency** (second run: `changed=0`)
- Keeping `command`/`shell` honest with `changed_when` and `creates`; using the same playbook to detect and fix drift; `ansible-doc` and `ansible-lint`

## Before you start
- Docker Desktop on your laptop. The lab is four Ubuntu 24.04 containers standing in for servers (systemd + OpenSSH), on the private network `10.0.12.0/24` (pick another with `NET=` if it clashes with a network you already have).
- SSH hardening ideas come from Module 2 (keys only, no root logins, sudo).
- No cloud account is needed. **Cost: free.**

| Container | Hostname | Address | Role |
|---|---|---|---|
| `ans-control` | control | 10.0.12.10 | where Ansible runs (user `asha`) |
| `ans-web-01` | web-01 | 10.0.12.11 | web server |
| `ans-web-02` | web-02 | 10.0.12.12 | web server (the snowflake) |
| `ans-db-01` | db-01 | 10.0.12.21 | database server |

## Files in this folder
| File | What it is |
|---|---|
| `lab/up.sh`, `lab/down.sh`, `lab/addnode.sh` | start / remove the lab (reused by M12-L02); `addnode.sh` adds one more node |
| `lab/images/`, `lab/setup-*.sh` | the node and control images and their first-boot setup (asha's key uses the **fake** passphrase `demo-passphrase-123`) |
| `lab/stage-snowflake.sh` | stages the hook on web-02: nginx installed by hand, stopped, "maintenance" page |
| `project/` | the finished project `~/allcs-ansible`: `ansible.cfg`, `inventory.ini`, `inventory.yml`, `group_vars/all.yml`, `web.yml`, `node-id.yml`, plus `quick-fix.yml` (bad on purpose, for lint) and `web-typo.yml` (YAML indentation error on purpose) |
| `steps/` | earlier versions used along the way: `inventory-v1.ini`, `group_vars-all-v1.yml`, `web-v1.yml`, `web-v2.yml`, `node-id-v1.yml` |

## Follow along
1. Start the lab, with this folder copied onto the control node, and stage the snowflake on web-02:
   ```bash
   COPY="$PWD" bash lab/up.sh
   docker exec -i ans-web-02 bash < lab/stage-snowflake.sh
   ```
   Check both web servers the way the wiki checklist would:
   ```bash
   for h in web-01 web-02; do echo "== $h"; docker exec -u asha ans-$h bash -c 'dpkg-query -W nginx; systemctl is-active nginx; cat /var/www/html/index.html; id deploy'; done
   ```
   web-01: no nginx at all. web-02: `nginx 1.24.0-...`, `inactive`, `<p>maintenance - back soon</p>`. Neither has the `deploy` user.

2. Open a shell as Asha on the control node, unlock her key once, and install Ansible in a venv:
   ```bash
   docker exec -it -u asha -w /home/asha ans-control bash -l
   ```
   ```bash
   eval "$(ssh-agent -s)"
   ssh-add                       # passphrase: demo-passphrase-123 (fake, lab only)
   python3 --version
   python3 -m venv ~/.venvs/ansible
   ~/.venvs/ansible/bin/pip install ansible-core==2.21.5
   echo 'export PATH="$HOME/.venvs/ansible/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ansible --version
   apt-cache policy ansible-core | head -3
   ```
   `Python 3.12.3`, then `ansible [core 2.21.5]` with `config file = None`. Ubuntu's own package is `ansible-core 2.16.3`, about two years behind.

3. The inventory, as INI and as YAML:
   ```bash
   mkdir -p ~/allcs-ansible && cd ~/allcs-ansible
   cp ~/m12-l01-ansible-basics/steps/inventory-v1.ini inventory.ini
   cp ~/m12-l01-ansible-basics/project/inventory.yml .
   cat inventory.ini
   ansible-inventory -i inventory.ini --graph
   ansible-inventory -i inventory.yml --graph
   ```
   ```
   @all:
     |--@ungrouped:
     |--@web:
     |  |--web-01
     |  |--web-02
     |--@db:
     |  |--db-01
   ```

4. Move the user into `group_vars`, add `ansible.cfg`:
   ```bash
   cp ~/m12-l01-ansible-basics/project/inventory.ini .          # same, without [all:vars]
   mkdir -p group_vars host_vars && cp ~/m12-l01-ansible-basics/steps/group_vars-all-v1.yml group_vars/all.yml
   cp ~/m12-l01-ansible-basics/project/ansible.cfg .
   tree
   ansible-inventory --host web-01
   ansible --version | head -2
   ```
   `{"ansible_host": "10.0.12.11", "ansible_user": "asha"}` and `config file = /home/asha/allcs-ansible/ansible.cfg`.

5. First ping - and verify host keys the right way:
   ```bash
   ansible all -m ansible.builtin.ping
   ```
   All three `UNREACHABLE! ... Host key verification failed.` (known_hosts is empty). Do **not** turn off host key checking. Fetch the keys and print their fingerprints:
   ```bash
   ssh-keyscan -t ed25519 10.0.12.11 10.0.12.12 10.0.12.21 > /tmp/new-hosts
   ssh-keygen -lf /tmp/new-hosts
   ```
   Compare with each server's real fingerprint, read from its console (a second terminal on your laptop):
   ```bash
   for h in web-01 web-02 db-01; do docker exec ans-$h ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub; done
   ```
   They must match (yours differ from the video's `JXEl...`, `ycsu...`, `MfEK...`: every lab generates new keys). Then:
   ```bash
   cat /tmp/new-hosts >> ~/.ssh/known_hosts
   ansible all -m ansible.builtin.ping
   ```
   `SUCCESS ... "ping": "pong"` from all three, plus a warning about the discovered Python interpreter. Make it explicit and ping again:
   ```bash
   cp ~/m12-l01-ansible-basics/project/group_vars/all.yml group_vars/all.yml && cat group_vars/all.yml
   ansible all -m ansible.builtin.ping
   ```

6. Ad-hoc commands:
   ```bash
   ansible web -m ansible.builtin.command -a "hostname"
   ansible db-01 -m ansible.builtin.command -a 'cat /etc/hostname | tr a-z A-Z'
   ansible db-01 -m ansible.builtin.shell -a 'cat /etc/hostname | tr a-z A-Z'
   ansible db -m ansible.builtin.apt -a "name=tree state=present update_cache=true"
   ansible db -m ansible.builtin.apt -a "name=tree state=present update_cache=true" -b
   ansible db -m ansible.builtin.apt -a "name=tree state=present" -b
   ansible db-01 -m ansible.builtin.service -a "name=ssh state=started" -b
   ansible db -m ansible.builtin.copy -a "content='Authorised staff only.' dest=/etc/motd" -b
   ansible all -m ansible.builtin.user -a "name=deploy shell=/bin/bash" -b
   ansible db-01 -m ansible.builtin.setup -a "filter=ansible_distribution*"
   ansible all --limit web-01 -m ansible.builtin.command -a "id deploy"
   time ansible all -f 1 -a "sleep 2" > /dev/null
   time ansible all -a "sleep 2" > /dev/null
   ```
   What to notice: `command` always says `CHANGED`; with a pipe it fails (no shell), `shell` prints `DB-01`; `apt` without `-b` fails with `Permission denied` on apt's lists folder, with `-b` it is `CHANGED`, the second time `SUCCESS` (`changed: false`); `user` is `CHANGED` on all three; the facts say Ubuntu `24.04` `noble`; forks: about 7.2 s with `-f 1` vs 2.7 s with the default 5.

7. The playbook. Start with the first version (no `nginx -t` yet), check it, then dry-run:
   ```bash
   cp ~/m12-l01-ansible-basics/steps/web-v1.yml web.yml && cat web.yml
   ansible-playbook web.yml --syntax-check
   ansible-playbook web.yml --list-hosts
   ansible-playbook web.yml --check --diff
   ```
   The dry run fails: check mode needs `python3-apt` on the servers. Install it, then dry-run again:
   ```bash
   ansible web -m ansible.builtin.apt -a "name=python3-apt state=present update_cache=true" -b
   ansible-playbook web.yml --check --diff
   ```
   nginx `ok` on web-02, `changed` on web-01; the home page diff shows `-<p>maintenance - back soon</p>` / `+<p>Served by web-02</p>` on web-02; the last task fails on web-01 (in a dry run nginx was never installed - check mode can't see earlier tasks' effects).

8. The real run, then `curl`, then run it again:
   ```bash
   ansible-playbook web.yml
   curl -s 10.0.12.11; curl -s 10.0.12.12
   ansible-playbook web.yml
   ```
   ```
   web-01 : ok=4    changed=3    unreachable=0    failed=0 ...
   web-02 : ok=4    changed=2    unreachable=0    failed=0 ...
   ```
   Each server serves `<p>Served by web-0X</p>`. The second run: **`changed=0`** on both. That's idempotency.

9. Keep `command` honest:
   ```bash
   cp ~/m12-l01-ansible-basics/steps/web-v2.yml web.yml && ansible-playbook web.yml      # nginx -t says changed every run
   cp ~/m12-l01-ansible-basics/project/web.yml web.yml && ansible-playbook web.yml       # changed_when: false -> changed=0
   ```
   And `creates`:
   ```bash
   cp ~/m12-l01-ansible-basics/steps/node-id-v1.yml node-id.yml
   ansible-playbook node-id.yml; ansible db -a "cat /etc/allcs-node-id"
   ansible-playbook node-id.yml; ansible db -a "cat /etc/allcs-node-id"
   cp ~/m12-l01-ansible-basics/project/node-id.yml node-id.yml
   ansible-playbook node-id.yml -v; ansible db -a "cat /etc/allcs-node-id"
   ```
   Without `creates` the ID changes every run (`3939...` then `9a54...` in the video). With it: `ok ... Did not run command since '/etc/allcs-node-id' exists`, and the ID stays.

10. Drift, staged on web-02's console (a second terminal on your laptop):
    ```bash
    docker exec ans-web-02 bash -c "echo '<p>Diwali sale: 50% off</p>' >> /var/www/html/index.html; systemctl stop nginx; systemctl is-active nginx"
    ```
    Back on the control node - detect, then fix only web-02:
    ```bash
    ansible-playbook web.yml --check --diff
    ansible-playbook web.yml --limit web-02 --diff
    curl -s 10.0.12.12
    ```
    The diff shows `-<p>Diwali sale: 50% off</p>` and nginx would be started; the fix run reports `changed=2`.

11. Docs and lint:
    ```bash
    ansible-doc ansible.builtin.service | grep -A8 '^   state'
    ansible-doc -l 2>/dev/null | wc -l
    ansible-doc -l 2>/dev/null | grep -E "^ansible.builtin.(apt|copy|user) "
    pip install -q ansible-lint==26.10.1
    ansible-lint --version
    git init -q 2>/dev/null; cp ~/m12-l01-ansible-basics/project/quick-fix.yml .
    ansible-lint quick-fix.yml
    ansible-lint web.yml node-id.yml
    ```
    `quick-fix.yml`: **11 violations** (`name[play]`, `yaml[truthy]`, `command-instead-of-module`, `fqcn[action-core]`, `no-changed-when`, `risky-file-permissions`...). `web.yml node-id.yml`: `Passed: 0 failure(s) ... 'production'`.

12. Pitfall: YAML indentation:
    ```bash
    cp ~/m12-l01-ansible-basics/project/web-typo.yml . && ansible-playbook web-typo.yml --syntax-check
    ```
    `YAML parsing failed: While parsing a block mapping did not find expected key ... web-typo.yml:10:8`.

13. Pitfall: why host key checking stays on. Give db-01 brand-new host keys (as if another machine took its address), from your laptop:
    ```bash
    docker exec ans-db-01 bash -c 'rm /etc/ssh/ssh_host_* && ssh-keygen -A && systemctl restart ssh'
    ```
    On the control node:
    ```bash
    ansible db-01 -m ansible.builtin.ping
    ANSIBLE_HOST_KEY_CHECKING=False ansible db-01 -m ansible.builtin.ping
    ```
    The first: `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` and Ansible refuses. The second: `pong`, no questions asked - that could have been an attacker's machine receiving your playbook with sudo. The right fix: check the new fingerprint on the console (`docker exec ans-db-01 ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`), then:
    ```bash
    ssh-keygen -R 10.0.12.21
    ssh-keyscan -t ed25519 10.0.12.21 2>/dev/null | tee -a ~/.ssh/known_hosts | ssh-keygen -lf -
    ansible db-01 -m ansible.builtin.ping
    ```

## Common mistakes
- `shell` for everything: it reports changed forever and check mode skips it. Use a module.
- Forgetting `become`: `Permission denied` on the apt lists folder means add `-b` / `become: true`.
- YAML indentation: run `--syntax-check` before anything reaches a server.
- Turning off host key checking "just for now": verify fingerprints instead.
- Running against `all` by accident: target a group, use `--limit`, check `--list-hosts`, do a `--check --diff` run first.

## Clean up
Free and local. Later Module 12 lessons start their own copy of this lab, so remove this one when you finish (from this folder on your laptop):
```bash
bash lab/down.sh
```

## Next
[M12-L02 · Ansible in Practice](../m12-l02-ansible-in-practice/)
