# hc - a server health-check toolkit

Built in the DevOps course, Module 3 - Build 1. One Bash command, `hc`, checks a Linux server every
5 minutes and sends an alert to a chat webhook when its state changes.

## What it checks

| Check | How | WARN / CRIT (defaults) |
|---|---|---|
| disk space, per mount | `df -P` | 80% / 90% used |
| inodes, per mount | `df -Pi` | 80% / 90% used |
| memory | `MemAvailable` in `/proc/meminfo` | 20% / 10% or less available |
| load | 1-minute load average / CPUs | 1.5 / 3 |
| services | `systemctl is-active` | anything but `active` is CRIT |
| HTTP endpoints | `lib/http_check.py` (timeout, JSON `status`) | JSON status not `ok` is WARN; error or no answer is CRIT |

The worst result is the exit code: `0` OK, `1` WARN, `2` CRIT, `3` UNKNOWN (usage or config error) -
the same convention as Nagios-style monitoring plugins.

## Layout

```
bin/hc               the entry point (Bash)
lib/checks.sh        config loader and the system checks (Bash)
lib/http_check.py    HTTP checks (Python, standard library only)
lib/report.py        JSON output and the webhook alert (Python)
conf/hc.conf         settings: thresholds, mounts, services, endpoints, webhook
systemd/hc.service   oneshot service, runs as user hc, hardened
systemd/hc.timer     every 5 minutes
systemd/demo-30s.conf  optional drop-in for demos: every 30 seconds
logrotate/hc         weekly, keep 8, compressed
install.sh           idempotent installer
tests/run.sh         plain Bash test runner (+ three test configs)
```

Installed to standard Linux paths: code in `/opt/hc`, settings in `/etc/hc/hc.conf` (mode 640, root:hc,
because a webhook URL is a secret), log in `/var/log/hc/hc.log`, state in `/var/lib/hc/state`.

## Install

Needs Ubuntu 24.04 (or any systemd Linux) with `python3`, `logrotate` and `util-linux` (`flock`).

```
sudo ./install.sh          # safe to run again: prints "unchanged" for files that are already right
systemctl list-timers hc.timer
sudo systemctl start hc    # one run now, exactly as the timer runs it
journalctl -u hc -n 14
```

Edit `/etc/hc/hc.conf` for your server. `install.sh` never overwrites it.

## Use

```
sudo hc --dry-run          # run the checks by hand: writes nothing, sends nothing
sudo hc -n --json          # the same, as JSON
hc -h
```

Real runs happen only through systemd (as user `hc`); `hc` refuses to run as root without `--dry-run`.

## Alerts

`hc` keeps the last state in `/var/lib/hc/state`. It sends a POST with JSON to `WEBHOOK_URL` (HTTPS only in production) only when the
state changes (OK -> WARN, WARN -> CRIT, CRIT -> OK, ...). The body has a Slack-style `text` field plus
`host`, `from`, `to` and `problems`. The new state is saved only after the webhook answered, so a failed
alert is retried on the next run.

## Develop

```
tests/run.sh                                    # as a normal user
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:v0.11.0 -x bin/hc lib/checks.sh install.sh tests/run.sh
```

## At real scale

For a fleet, expose metrics to Prometheus and route alerts with Alertmanager (course Module 16), and roll the
toolkit out with Ansible (Module 12). Ideas to extend it: a certificate-expiry check, a heartbeat so you notice
when `hc` itself stops, and a repeat alert when a CRIT lasts too long.

## On call

Runbook: https://wiki.example.com/ops/hc (what each alert means, and what to do).

`CERT_HOSTS`: the public hosts whose TLS certificates hc checks (space-separated).
