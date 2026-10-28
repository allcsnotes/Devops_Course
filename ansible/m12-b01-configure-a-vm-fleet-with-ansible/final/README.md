# allcs-fleet - the allcsvideos VM fleet, configured with Ansible

Built in the DevOps course, Module 12 - Build 1 ("Configure a VM Fleet with Ansible"). It takes bare Ubuntu 24.04
servers (one load balancer, four or more web servers) to a hardened, load-balanced fleet running Course Copilot,
and ships new releases with zero downtime.

Tested 21 Oct 2026 with ansible-core 2.21.5 (pip, in a venv on the control node), ansible.posix 2.2.2 and
community.general 13.5.0, against Ubuntu 24.04 servers. In the course lab those servers are Docker containers with
systemd as PID 1 and OpenSSH, standing in for VMs (`../lab/up.sh`, network 10.0.126.0/24).

## Layout

```
ansible.cfg              inventory, vault password file (outside the repo), interpreter, forks 10,
                         ansible.posix.timer callback, SSH pipelining
inventory.ini            [lb] lb-01 · [web] web-01..05
requirements.yml         collections, pinned
site.yml                 all -> common, hardening · web -> nginx, app · lb -> lb · all -> hc_toolkit
rolling.yml              zero-downtime release: serial "25%", max_fail_percentage 0, drain -> update -> check -> back
tasks/lb-member.yml      take one web server out of / back into every load balancer (lineinfile "down",
                         nginx -t, reload, delegated to the lb group)
group_vars/all/vars.yml  ansible_user, bastion_ip, admin_users (name, comment, public key)
group_vars/all/vault.yml ENCRYPTED (ansible-vault, AES256): vault_hc_webhook_url (a FAKE demo value)
group_vars/web.yml       copilot_version (the pinned release), nginx_app_port, ufw: 80 only from the lb group
group_vars/lb.yml        ufw: 80 from anywhere
roles/common             base packages, time zone (UTC), timesyncd NTP drop-in, unattended-upgrades config,
                         admins + sshusers groups, admin users, exclusive authorized keys, sudoers (visudo -cf %s)
roles/hardening          lockout guard (assert: ansible_user is in an allowed group), sshd drop-in
                         (no root, no passwords, AllowGroups; validate: sshd -t -f %s), ufw (22 from the bastion
                         first, service ports, then default deny + enable)
roles/nginx              nginx, nginx.conf (validate: nginx -t -c %s, includes conf.d only), on web servers a
                         proxy from :80 to the app on 127.0.0.1; handlers "nginx config changed" (test, reload)
roles/lb                 depends on nginx; lb.conf with one upstream server per host in groups['web']
roles/app                Course Copilot release tarball -> /opt/copilot/releases/<version>, shared venv,
                         /etc/copilot/copilot.env, systemd unit (User=copilot, 127.0.0.1:8000, sandboxing),
                         current symlink, flush_handlers, health check with until/retries
roles/hc_toolkit         the M03-B01 health-check toolkit (unchanged from M12-L02), hc.conf with the vaulted
                         webhook URL (no_log), systemd timer
```

Release artifacts are not in this repo: `copilot_artifact_dir` (default `~/releases` on the control node) holds
`copilot-<version>.tar.gz` (in the lab built by `../release/make-release.sh` from `../release/src/<version>`; in a real
team the CI pipeline builds and stores them).

## Use

```
python3 -m venv ~/.venvs/ansible && ~/.venvs/ansible/bin/pip install ansible-core==2.21.5
ansible-galaxy collection install -r requirements.yml
(umask 077; echo '<your vault password>' > ~/.vault-pass.txt)   # lab value: demo-vault-pass-123 (FAKE)
ansible-playbook site.yml                      # bare -> serving; a second run reports changed=0
ansible-playbook site.yml --limit web-05,lb    # a new web server, plus the LB so its pool learns about it
# release: edit copilot_version in group_vars/web.yml, commit, then
ansible-playbook rolling.yml                   # one quarter of the web servers at a time, stops on the first failure
git revert --no-edit HEAD && ansible-playbook rolling.yml   # roll back: only the servers that differ change
```

## What the course lab measured (real runs, 21 Oct 2026)

- First runs, step by step: common 1 min 4 s (9 changes per server), hardening 37 s (5), nginx + app 1 min 20 s
  (17 per web server), lb 56 s (6 on lb-01), hc_toolkit 1 min 4 s (8). Full idempotent run: changed=0 on all five, 2 min 6 s.
- rolling.yml 1.8.0 -> 1.9.0 under 40 requests/s: 2 min 14 s, 6,103 requests, 0 failed, 0 retried by nginx.
- Staged bad release 1.9.1 (course index renamed in the tarball, code unchanged): health check 503 on web-01,
  "NO MORE HOSTS LEFT" after one server (39 s), web-01 stayed out of the pool; 5,572 requests, 0 failed.
  `git revert` + rolling.yml: web-01 changed=5, the others changed=0.
- Staged sshd typo (AllowGroup): validate failed on all five, nothing replaced, nothing restarted.
  Staged override to a group nobody is in: the lockout guard refused.
- web-05 from bare to serving: 3 min 19 s (web-05 changed=39, lb-01 changed=2), 8,885 requests during the run, 0 failed.

## Notes

- With `serial` of one host per batch, a failed batch already stops the play; `max_fail_percentage: 0` keeps that
  rule when batches grow (the percentage must be exceeded: docs.ansible.com, "Setting a maximum failure percentage").
- Running `site.yml` resets every server to "up" in lb.conf (the template is the desired state). Don't run it in the
  middle of a rollout.
- systemd-timesyncd has `ConditionVirtualization=!container`: it is enabled but skipped in the container lab (the host
  owns the clock); on a real VM it syncs with `common_ntp_servers`.
- fail2ban is not included: password logins are off and SSH is reachable only from the bastion.
- ansible-lint 26.10.1 reports style findings only: lowercase handler names (`name[casing]`) and role variables without
  a role prefix (`var-naming[no-role-prefix]`).
- At real scale: a dynamic inventory (amazon.aws `aws_ec2` plugin, groups from tags; example in
  `../stages/scale/prod.aws_ec2.yml`, not run in the lab), AWX / Ansible Automation Platform to run it, golden images
  with Packer (M12-L03), and Kubernetes Deployments for rolling updates (Module 13).
