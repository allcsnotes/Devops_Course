# allcs-ansible - the allcsvideos fleet, as Ansible roles

Built in the DevOps course, Module 12 - Lesson 2 ("Ansible in Practice"). It replaces the ~300-line
copy-paste `site.yml` from the start of that lesson. Reused by M12-B01 ("Configure a fleet of VMs").

Tested with ansible-core 2.21.5 (pip, in a venv on the control node) and the collection
ansible.posix 2.2.2, against Ubuntu 24.04 servers (systemd + OpenSSH) in the course's Docker lab
(`../../m12-l01-ansible-basics/lab/up.sh` with `NET=10.0.122`).

## Layout

```
ansible.cfg            inventory + vault password file (outside the repo)
inventory.ini          [web] web-01..03, [db] db-01
requirements.yml       collections, pinned (ansible.posix 2.2.2)
site.yml               all -> common, hc_toolkit · web -> nginx, app_config (each role has a tag)
group_vars/all.yml     ansible_user, app_env, common_users (list of dicts with public keys)
group_vars/web.yml     nginx_server_name, nginx_worker_connections, api_backends, hc_services, hc_endpoints
group_vars/db/vars.yml db_name, db_user, db_password: "{{ vault_db_password }}", ssh_allow_users
group_vars/db/vault.yml  ENCRYPTED (ansible-vault, AES256): vault_db_password (a FAKE demo value)
host_vars/web-02.yml   the canary: app_log_level debug, app_features
roles/common           base packages, users + authorized keys (loop over dicts), sshd hardening template
                       (validate: sshd -t -f %s, handler: restart ssh)
roles/nginx            nginx.conf.j2 (validate: nginx -t -c %s), index.html.j2, handlers listening to
                       "nginx config changed" (nginx -t, then reload), flush_handlers, /health check
roles/hc_toolkit       the M03-B01 health-check toolkit (files/hc, unchanged) + hc.conf.j2 per host,
                       systemd units, logrotate rule, hc.timer enabled
roles/app_config       /etc/allcsvideos/app.env (mode 0600, no_log: true - it holds the DB password)
                       and features.yml (to_nice_yaml)
```

Role `defaults/` hold the knobs (lowest precedence: group_vars and host_vars override them). Nothing lives
in role `vars/` on purpose: role vars beat group_vars and host_vars (precedence list:
https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html, "Understanding variable precedence").

## Use

```
python3 -m venv ~/.venvs/ansible && ~/.venvs/ansible/bin/pip install ansible-core==2.21.5
ansible-galaxy collection install -r requirements.yml
(umask 077; echo '<your vault password>' > ~/.vault-pass.txt)   # lab value: demo-vault-pass-123 (FAKE)
ansible-playbook site.yml --check --diff     # what would change
ansible-playbook site.yml                    # converge the fleet (a second run reports changed=0)
ansible-playbook site.yml --tags nginx       # one role
ansible-playbook site.yml --limit web-03     # one new server
ansible-vault view group_vars/db/vault.yml
```

Without `~/.vault-pass.txt`, use `--ask-vault-pass`. Never commit the password file (`.gitignore` has
`.vault-pass*`). A secret that was ever committed in plain text is burned: rotate it (the lesson did).

## Notes

- `--diff` prints file contents: keep `no_log: true` on tasks that render secrets.
- A failed task stops the play before handlers run; a later run sees no change and never reloads.
  Use `--force-handlers` (or `force_handlers: true`) when a reload must not be lost.
- The lab webhook URL in `hc_toolkit` is a dead lab address; a real webhook URL is a secret (vault it).
- `ansible-lint` 26.10.1 reports style findings only: lowercase handler names (`name[casing]`) and role
  variables without a role prefix (`var-naming[no-role-prefix]`, e.g. `api_backends`).
