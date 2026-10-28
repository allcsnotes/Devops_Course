# Troubleshooting labs (DevOps course, Module 20 · Build 3)

Ten real, injectable production faults on a small allcsvideos stack, and one method to find them.
Everything runs in Docker; only the `docker` CLI runs on your machine. All credentials are FAKE lab values.

## The stack (`zsh lab.sh up`)

| Machine | What it is |
|---|---|
| web-01 (10.0.205.10) | Ubuntu 24.04 + systemd: nginx (TLS on 443) -> allcs-api (Python, psycopg2); /var/log/allcs is a 64 MB disk |
| ns1 (10.0.205.53) | Ubuntu 24.04 + systemd: BIND 9, authoritative for allcsvideos.test |
| db-01 (10.0.205.20) | PostgreSQL 18.6, max_connections=20 |
| ops | your workstation: kubectl, kind, curl, dig, openssl, psql, git, gitleaks (`zsh lab.sh ops`) |
| kind cluster m21lab-tl | one node; namespace allcs: catalog (2 pods + Service), thumbs (1 pod + Service), client |

Pinned versions (checked 2026-10-21): ubuntu:24.04 (24.04.5 LTS; nginx 1.24.0, BIND 9.18.39, Python 3.12.3, OpenSSL 3.0.13),
postgres:18.6-alpine3.24, docker:29.5.3-cli, kind v0.33.0, kindest/node v1.37.0, kubectl v1.37.1,
zricethezav/gitleaks:v8.30.1, busybox:1.37.0, gcr.io/distroless/python3-debian13 (by digest).

## Play

```
zsh lab.sh up            # build and start everything (about 3 minutes)
zsh lab.sh status        # the user's view: everything should be ok
./break.sh 3             # inject scenario 3 (prints a vague hint, like an alert)
zsh lab.sh ops           # investigate as asha@ops; zsh lab.sh sh web01 / sh ns1 for the servers
note "S3 symptom: ..."   # one line for the timeline (also: S3 cause: ..., S3 fixed: ...)
score                    # time to diagnose and to fix, per scenario, from your notes
./reset.sh 3             # put it back (or: ./reset.sh all)
zsh lab.sh down          # remove everything; zsh lab.sh check must print nothing
```

## The method

1. Observe the symptom as a user (curl, rollout status).
2. What changed? (a deploy, a config, a record, a job)
3. Go layer by layer: DNS, network, TLS, process, resources, app logs, config.
4. Form a hypothesis. 5. Test it without changing anything.
6. Fix one thing. 7. Verify as a user. 8. Write one line for the postmortem (`note`).

Scenario cards (symptom, first 3 commands, root cause, fix, prevention): `scenarios.md`. Play first, read after.

## Add your own scenario

Add a case to `break.sh` (the fault and a vague `log` hint), the undo to `reset.sh`, a check to `lab.sh status`
if it needs one, and a card to `scenarios.md`.
