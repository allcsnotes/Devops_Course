# M12-L02 · Ansible in Practice
> Video: Module 12, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- **Variables**: inventory, `group_vars`, `host_vars`, play vars, extra vars, facts and magic variables - and **precedence** (role defaults lowest, extra vars highest)
- `register`, `when` and `loop` (over a list of dicts)
- **Templates** (Jinja2: `{{ }}`, `{% %}`, filters, `hostvars`) with `validate`, and **handlers** that run only on real change (`notify`, `listen`, `flush_handlers`)
- **Roles** (`ansible-galaxy role init`), defaults vs vars, and **collections** pinned in `requirements.yml` (`ansible.posix 2.2.2`)
- **Ansible Vault**: encrypt secrets in git, `no_log`, a password file outside the repo, vault IDs
- Running a big project: tags, `--start-at-task`, `serial`, adding a new server with `--limit`, and the pitfalls (lost handlers, Jinja whitespace)

## Before you start
- Docker Desktop, and the lab from [M12-L01](../m12-l01-ansible-basics/) (this lesson starts its own copy with Ansible pre-installed, on `10.0.122.0/24`, the addresses used in this lesson's files).
- **Cost: free**, all local.
- All secrets here are **fake teaching values**: SSH key passphrase `demo-passphrase-123`, vault password `demo-vault-pass-123`, prod vault-ID password `demo-prod-pass-123`, DB password `demo-db-password-123` (rotated to `demo-db-password-456`). The public SSH keys in `group_vars/all.yml` are demo keys whose private halves were deleted.

## Files in this folder
| File | What it is |
|---|---|
| `final/` | the finished repository `allcs-ansible`: `site.yml`, roles `common`, `hc_toolkit`, `nginx`, `app_config`, `group_vars` (with `db/vault.yml` **encrypted** with the fake password `demo-vault-pass-123`), `host_vars`, `requirements.yml`, `.gitignore`, its own README |
| `stages/hook/` | the "before" state: the 292-line copy-paste `site.yml`, lesson 1's `web.yml`, the hc toolkit files |
| `stages/stage1/` | variables, templates and handlers stage: `vars-demo.yml` (+ `.v2`), `checks.yml`, `web.v1.yml`, `web.v2.yml`, `templates/` (incl. `nginx.conf.broken.j2` and `nginx.conf.gzip.j2`), `group_vars/`, `host_vars/` |
| `stages/roles-stage/` | the first roles version (with the **staged** `roles/nginx/vars/main.yml` mistake) |
| `stages/pitfalls/` | `web-02.canary.yml`, `index.broken.html.j2`, `upstream.j2`, `upstream-fixed.j2` |
| `stages/site.serial.yml`, `stages/inventory.ini`, `stages/ansible.cfg`, `stages/group_vars/all.yml` | supporting files |
| `lab/stage-hook.sh` | builds the "before" git repo with back-dated commits and the plaintext (fake) password |

## Follow along
All commands after step 1 run as **asha on the control node** in `~/allcs-ansible`. `$L` below is this lesson folder on the control node.

1. Start the lab with Ansible installed and this folder copied in, then open a shell and stage the hook:
   ```bash
   NET=10.0.122 COPY="$PWD" bash ../m12-l01-ansible-basics/lab/up.sh install
   docker exec -it -u asha -w /home/asha ans-control bash -l
   ```
   ```bash
   L=~/m12-l02-ansible-in-practice
   eval "$(ssh-agent -s)"; ssh-add          # demo-passphrase-123 (fake)
   ssh-keyscan -t ed25519 10.0.122.11 10.0.122.12 10.0.122.21 >> ~/.ssh/known_hosts   # in real life: compare fingerprints first (M12-L01)
   bash $L/lab/stage-hook.sh && cd ~/allcs-ansible
   ```

2. **The hook**: a playbook nobody wants to touch:
   ```bash
   ansible-playbook site.yml
   wc -l site.yml; grep -c "name:" site.yml; grep -n "web-0[12]" site.yml
   ansible-playbook site.yml
   grep -n "db_password" site.yml; git log --oneline; git log --oneline -S demo-db-password-123
   ansible web-01 -a 'ls -l /etc/allcsvideos/app.env'; ansible web-01 -a 'cat /etc/allcsvideos/app.env'
   ```
   `292 site.yml`, `51` names, a whole play per web server; the **second run still reports changes** (nginx and sshd restart every time); the password is in git history; `app.env` is mode `644`, readable by every user.

3. **Variables**:
   ```bash
   cp $L/stages/stage1/group_vars/{all,web,db}.yml group_vars/ && mkdir -p host_vars && cp $L/stages/stage1/host_vars/web-02.yml host_vars/
   cp $L/stages/stage1/vars-demo.yml $L/stages/stage1/checks.yml .
   tree group_vars host_vars
   ansible web -m debug -a "var=app_log_level"
   ansible-playbook vars-demo.yml
   ansible-playbook vars-demo.yml -e app_log_level=error
   cp $L/stages/stage1/vars-demo.v2.yml vars-demo.yml && ansible-playbook vars-demo.yml
   ansible-playbook checks.yml
   ```
   `info` / `debug` (host vars beat group vars); then `warning` everywhere (play vars beat host vars); `error` everywhere (extra vars always win); without play vars: web-01 `info`, web-02 `debug`, db-01 `VARIABLE IS NOT DEFINED!`. `checks.yml`: `nginx -v` returns 0 on the web servers and 2 on db-01; the `when` message runs only on db-01; `loop` walks the users.

4. **Templates and validate**:
   ```bash
   mkdir -p templates && cp $L/stages/stage1/templates/{nginx.conf,index.html,app.env,features.yml}.j2 templates/
   cp $L/stages/stage1/web.v1.yml web.yml
   ansible-playbook web.yml --diff
   ```
   The diff shows each rendered file per host (`PRODUCTION` in the home page; web-02's `app.env` with 20 workers from 10 CPUs and the DB password - remember that), then `RUNNING HANDLER [reload nginx]` once per server.
   Break it on purpose (gzip without a semicolon), then fix it:
   ```bash
   cp $L/stages/stage1/templates/nginx.conf.broken.j2 templates/nginx.conf.j2 && ansible-playbook web.yml --diff
   curl -s web-01/health; curl -s web-02/health
   cp $L/stages/stage1/templates/nginx.conf.gzip.j2 templates/nginx.conf.j2 && ansible-playbook web.yml --diff
   ```
   `invalid number of arguments in "gzip" directive ... failed to validate` - the real `nginx.conf` was never touched and both servers still answer `/health`. The fix shows just the two gzip lines and one reload.

5. **Handlers**:
   ```bash
   ansible-playbook web.yml
   cp $L/stages/stage1/group_vars/web.v2.yml group_vars/web.yml && cp $L/stages/stage1/web.v2.yml web.yml
   ansible-playbook web.yml --diff
   ```
   First: `changed=0`, no handler. Then (worker connections 1024, `listen: nginx config changed`, `meta: flush_handlers`, a `uri` health check): both handlers run **mid-play**, before the health check.

6. **Roles**:
   ```bash
   git add -A && git commit -qm "variables, templates, handlers"
   ansible-galaxy role init roles/nginx; tree roles/nginx
   for r in common hc_toolkit app_config; do ansible-galaxy role init roles/$r; done
   rm -rf roles && cp -r $L/stages/roles-stage/roles $L/stages/roles-stage/site.yml . && cp $L/stages/roles-stage/group_vars/*.yml group_vars/
   git rm -q --cached web.yml vars-demo.yml checks.yml 2>/dev/null; rm -rf web.yml vars-demo.yml checks.yml templates files
   tree -I files --noreport; tree roles/hc_toolkit
   ansible-playbook site.yml
   ```
   The last run fails: `couldn't resolve module/action 'ansible.posix.authorized_key'` - that module is in a collection, not in ansible-core.

7. **Collections**, then the role-vars surprise:
   ```bash
   cp $L/final/requirements.yml . && cat requirements.yml
   ansible-galaxy collection install -r requirements.yml
   ansible-galaxy collection list ansible.posix
   ansible-playbook site.yml --diff
   ```
   `ansible.posix 2.2.2`. The run works, but `worker_connections` goes **1024 -> 768**: `roles/nginx/vars/main.yml` (precedence 15) beats `group_vars` (staged mistake). Move it to defaults:
   ```bash
   rm -rf roles/nginx/vars && cp $L/final/roles/nginx/defaults/main.yml roles/nginx/defaults/main.yml
   ansible-playbook site.yml --diff
   ```
   Back to 1024; db-01 reports no changes.

8. **Vault**: find the secret, rotate it, encrypt it:
   ```bash
   git add -A && git commit -qm "roles"
   git grep -n demo-db-password; git log --oneline -S demo-db-password-123
   mkdir -p group_vars/db && git mv group_vars/db.yml group_vars/db/vars.yml
   EDITOR=nano ansible-vault create group_vars/db/vault.yml
   ```
   Type the vault password `demo-vault-pass-123` twice; in nano write one line, `vault_db_password: demo-db-password-456`, save and exit. Then:
   ```bash
   cat group_vars/db/vault.yml          # $ANSIBLE_VAULT;1.1;AES256 + ciphertext
   ansible-vault view group_vars/db/vault.yml
   cp $L/final/group_vars/db/vars.yml group_vars/db/vars.yml && cat group_vars/db/vars.yml   # db_password: "{{ vault_db_password }}"
   ansible-playbook site.yml
   ```
   `Attempting to decrypt but no vault secrets found`. Dry run with the password:
   ```bash
   ansible-playbook site.yml --ask-vault-pass --check --diff
   cp $L/final/roles/nginx/tasks/main.yml roles/nginx/tasks/main.yml        # check_mode: false on the read-only health GET
   ansible-playbook site.yml --ask-vault-pass --check --diff
   ```
   The first dry run fails (the `uri` check is skipped in check mode); the second works - and **prints both passwords** in the diff. Fix with `no_log`, then run:
   ```bash
   cp $L/final/roles/app_config/tasks/main.yml roles/app_config/tasks/main.yml   # no_log: true on app.env
   ansible-playbook site.yml --ask-vault-pass --diff
   ```

9. A password file **outside** the repo, and git hygiene:
   ```bash
   (umask 077; echo demo-vault-pass-123 > ~/.vault-pass.txt)
   ls -l ~/.vault-pass.txt
   cp $L/final/ansible.cfg $L/final/.gitignore . && cat ansible.cfg .gitignore
   ansible-playbook site.yml | tail -5
   ansible-vault edit group_vars/db/vault.yml          # no prompt now; save to re-encrypt
   git add -A && git status --short
   git check-ignore -v ~/allcs-ansible/.vault-pass.txt; echo "exit $?"
   git commit -qm "vault the db password"
   ```
   `-rw------- ... .vault-pass.txt`, `changed=0` everywhere, and `.gitignore` keeps any `.vault-pass*` out.
   Vault IDs (one password per environment; fake values, temporary file):
   ```bash
   echo 'prod_api_token: demo-prod-token-789' > /tmp/prod.yml
   ansible-vault encrypt --vault-id prod@prompt --encrypt-vault-id prod /tmp/prod.yml     # password: demo-prod-pass-123
   head -2 /tmp/prod.yml; rm /tmp/prod.yml
   ```
   Header `$ANSIBLE_VAULT;1.2;AES256;prod`.

10. **Driving a big project**:
    ```bash
    ansible-playbook site.yml --list-tags
    ansible-playbook site.yml --tags app -v
    ansible-playbook site.yml --start-at-task "nginx : Render nginx.conf"
    cp $L/stages/site.serial.yml site.yml && ansible-playbook site.yml --tags nginx
    cp $L/final/site.yml site.yml
    ```
    With `-v` the `app.env` result is censored (`no_log`). With `serial: 1`, web-01 finishes completely before web-02 starts.

11. **Add web-03** (on your laptop, from this folder, add the node; then back on the control node):
    ```bash
    NET=10.0.122 bash ../m12-l01-ansible-basics/lab/addnode.sh web-03 13
    ```
    ```bash
    cp $L/final/inventory.ini . && git diff inventory.ini
    ssh-keyscan -t ed25519 10.0.122.13 >> ~/.ssh/known_hosts
    ansible-playbook site.yml --limit web-03
    for h in web-01 web-02 web-03; do curl -s $h/health; done
    ansible web-03 -b -m shell -a 'systemctl start hc; journalctl -u hc -o cat --no-pager | tail -7'
    ansible web-03 -a 'systemctl list-timers hc.timer --no-pager'
    ansible-playbook site.yml
    ```
    web-03: **22 changes, 0 failures**; all three answer `/health`; `hc` reports every check ok and the timer is scheduled; the whole fleet then: `changed=0` on 4 hosts.

12. **Pitfall: lost handlers** (staged):
    ```bash
    cp $L/stages/pitfalls/web-02.canary.yml host_vars/web-02.yml && cp $L/stages/pitfalls/index.broken.html.j2 roles/nginx/templates/index.html.j2
    ansible-playbook site.yml --limit web-02 --tags nginx --diff
    cp $L/final/roles/nginx/templates/index.html.j2 roles/nginx/templates/
    ansible-playbook site.yml --limit web-02 --tags nginx | tail -3
    ansible web-02 -a "grep -o canary /etc/nginx/nginx.conf"; curl -s web-02/health
    ansible web-02 -b -m service -a "name=nginx state=reloaded" | head -3; curl -s web-02/health
    ```
    The config changed to canary, then the home page task failed and the play stopped **before the handlers**. The re-run sees no change, so nothing reloads: the file says `canary`, nginx still answers `production` until a manual reload. Prevent it with `--force-handlers`:
    ```bash
    cp $L/final/host_vars/web-02.yml host_vars/ && cp $L/stages/pitfalls/index.broken.html.j2 roles/nginx/templates/index.html.j2
    ansible-playbook site.yml --limit web-02 --tags nginx --force-handlers
    curl -s web-02/health
    cp $L/final/roles/nginx/templates/index.html.j2 roles/nginx/templates/ && ansible-playbook site.yml --limit web-02
    ```

13. **Pitfall: Jinja whitespace**:
    ```bash
    cp $L/stages/pitfalls/upstream*.j2 .
    cat upstream.j2
    ansible web-01 -m template -a 'src=upstream.j2 dest=/tmp/up.conf' > /dev/null; ansible web-01 -a 'cat -A /tmp/up.conf'
    head -1 upstream-fixed.j2
    ansible web-01 -m template -a 'src=upstream-fixed.j2 dest=/tmp/up.conf' > /dev/null; ansible web-01 -a 'cat -A /tmp/up.conf'
    rm upstream*.j2
    ```
    Indented `{% %}` tags leave 8 spaces on each `server` line; `#jinja2: lstrip_blocks: True` on the first line strips them.

At the end, `diff -r -x .git ~/allcs-ansible $L/final` should show only the README.

## Common mistakes
- Variable precedence surprises: keep knobs in **role defaults**, override in group/host vars, use extra vars only for one-off runs; avoid play vars and role `vars/` for knobs.
- Secrets in plain text and in logs: vault the files, **rotate** anything ever committed, `no_log: true` on tasks that render secrets (`--diff` prints file contents).
- Handlers that never run after a failed task: `--force-handlers` / `force_handlers: true`.
- Giant roles: one role per job, its defaults are its interface.
- Whitespace in Jinja2 templates: `lstrip_blocks` or `{%-  -%}`.

## Clean up
On your laptop, from this folder (removes all lab containers including web-03):
```bash
bash ../m12-l01-ansible-basics/lab/down.sh
```

## Next
[M12-L03 · Mutable vs Immutable Infrastructure](../m12-l03-mutable-vs-immutable-infrastructure/)
