# M03-B01 · Build a Server Health-Check Toolkit
> Video: Module 3, Build 1. Watch it first, then follow along here.

Rahul's goal for this build, in one sentence: "I want to know before Lukas does."
Asha combines everything from Module 3 into one real tool, `hc` (short for health check).

## What you'll learn
- Design a checker where every check returns the same three fields (severity, name, detail), and the worst
  severity becomes the exit code: `0` OK, `1` WARN, `2` CRIT, `3` UNKNOWN (the Nagios-style plugin convention).
- Mix Bash and Python in one tool: Bash glues the system commands, Python handles HTTP and JSON.
- Alert on a change, not on every run: keep the last state in a file and save it only after the alert went out.
- Make it installable: standard Linux paths, a config read as data (never `source`d), a hardened systemd
  service + timer, logrotate, an install script you can safely run twice, a dry run mode, tests and shellcheck.
- Break it on purpose and watch the alerts arrive: OK -> WARN -> CRIT -> OK.

## Before you start
- Docker Desktop (any OS) and a Bash shell. On Windows, use WSL or Git Bash for the `.sh` scripts.
- The earlier Module 3 lessons (Bash scripting, strict mode, `flock`, systemd timers, logrotate, `healthcheck.py`).
  M02-L03 showed the "systemd in a container" recipe the lab uses.
- No earlier lesson folder is needed: everything is in this folder.
- Images used (pinned, as in the video): `ubuntu:24.04` (web-01), `python:3.13.16-slim` (the webhook stand-in),
  `koalaman/shellcheck:v0.11.0`.

## Files in this folder
| File | What it is |
|---|---|
| `hc/` | **The toolkit itself.** Its own [README](hc/README.md) explains the layout, install and use. |
| `hc/bin/hc` | The entry point (Bash): options, lock, run checks, output, log line, alert on change. |
| `hc/lib/checks.sh` | Config loader (`load_conf`) and the system checks: disk, inodes, memory, load, services. |
| `hc/lib/http_check.py` | HTTP checks with timeouts and the JSON `status`, all endpoints at once. |
| `hc/lib/report.py` | `--json` output and the webhook alert. |
| `hc/conf/hc.conf` | Thresholds, mounts, services, endpoints, webhook URL. |
| `hc/systemd/hc.service`, `hc.timer` | Oneshot service as user `hc`, hardened; timer every 5 minutes. |
| `hc/systemd/demo-30s.conf` | Demo-only drop-in: run every 30 seconds. |
| `hc/logrotate/hc` | Weekly, keep 8, compressed. |
| `hc/install.sh` | Idempotent installer. |
| `hc/tests/` | `run.sh` (a tiny Bash test runner) and three test configs. |
| `lab/up.sh`, `lab/down.sh` | Start / remove the lab (two containers on one network). |
| `lab/Dockerfile` | web-01: Ubuntu 24.04 with systemd as PID 1, nginx, python3, logrotate. |
| `lab/setup-root.sh` | Turns the container into a fresh web-01 (user `asha`, nginx, API, `/data`, `~/hc`). |
| `lab/api.py`, `lab/allcsvideos-api.service` | A stand-in for the allcsvideos API: port 8080, `GET /health` -> `{"status": "ok"}`. |
| `lab/hooks.py` | A stand-in for a team chat webhook: prints every message it receives. Never a real external service. |

## Follow along

### 0. Start the lab
From this folder on your laptop:
```bash
bash lab/up.sh
```
This builds the web-01 image, starts `web-01` and `hooks` on the network `hc-lab`, and copies `hc/` to
`/home/asha/hc`. Keep a second terminal open on the "team chat":
```bash
docker logs -f hooks
```
In your main terminal, log in to web-01 as Asha. Every step below runs there, unless it says otherwise.
```bash
docker exec -it web-01 su - asha
```

### 1. The folder layout
```bash
cd ~/hc
find . -type f | sort
```
You should see `bin/hc`, `conf/hc.conf`, `install.sh`, `lib/` (3 files), `logrotate/hc`, `systemd/` (3 files)
and `tests/` (4 files). Open `conf/hc.conf`: pairs of WARN/CRIT thresholds, two mounts, two services, two
endpoints, a 3 second timeout, and the webhook. Then read `load_conf` in `lib/checks.sh`: the file is read as
data with a `while read` loop, unknown keys stop `hc`, and missing keys are reported.

### 2. The system checks: a first dry run
`lib/checks.sh` has `rate`, `check_disk` (`df -P` and `df -Pi`), `check_memory` (`MemAvailable`), `check_load`
(load per CPU, maths in `awk`), `check_service` (`systemctl is-active`) and `run_checks`.
```bash
bin/hc -c conf/hc.conf --dry-run; echo "exit $?"
```
You should see (your numbers will differ):
```
OK    disk /                   3% used
OK    inodes /                 1% used
OK    disk /data               15% used
...
OK    service allcsvideos-api  active
OK    storefront               HTTP 200 in 2 ms
OK    api                      HTTP 200 in 2 ms
dry run: would log: 2026-10-20T12:26:28+00:00 host=web-01 status=OK problems=""
exit 0
```

### 3. The HTTP checker on its own
```bash
python3 lib/http_check.py 3 storefront=http://localhost/ api=http://localhost:8080/health nope=http://localhost:9999/
```
```
OK      storefront      HTTP 200 in 2 ms
OK      api     HTTP 200 in 2 ms
CRIT    nope    unreachable: [Errno 111] Connection refused
```

### 4. hc itself: JSON and bad input
Read `bin/hc`: strict mode, `lib` found next to the real script, `STATE_DIRECTORY`/`LOGS_DIRECTORY` from
systemd, the `while`/`case` option loop, "never as root" and `flock` before a real run.
```bash
bin/hc -c conf/hc.conf -n --json 2> /dev/null
```
You should see `{"host": "web-01", "status": "OK", "checks": [ ... ]}` with one object per check.
```bash
bin/hc --nope; echo "exit $?"
bin/hc -c /etc/nope.conf -n; echo "exit $?"
```
```
hc: unknown option --nope (try -h)
exit 3
hc: cannot read config /etc/nope.conf
exit 3
```

### 5. Alerts
Still in `bin/hc`: `previous` is the last state (or OK). Only on a change does `hc` call `send_alert`, and the
new state is saved only if the alert went out. `lib/report.py` posts a Slack-style `text` field plus `host`,
`from`, `to` and `problems`, with a 5 second timeout.

### 6. The timer, service and logrotate rule
Read `systemd/hc.service` (Type oneshot, `User=hc`, `StateDirectory`/`LogsDirectory`, `SuccessExitStatus=1 2`,
four hardening lines), `systemd/hc.timer` (every 5 minutes, no `Persistent`) and `logrotate/hc` (no
`postrotate` needed: `hc` opens its log fresh on every run).

### 7. Tests
```bash
tests/run.sh
```
```
ok    rate 79 is OK
...
ok    alert failed: no state saved
12 passed, 0 failed
```

### 8. shellcheck (on your laptop, not in web-01)
Open a new terminal on your laptop, `cd` into this lesson's `hc/` folder and run:
```bash
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:v0.11.0 -x bin/hc lib/checks.sh install.sh tests/run.sh; echo "exit $?"
```
The files here are the fixed version, so you should see no findings and `exit 0`. In the video the first draft
had two warnings and four notes. The fixes, already applied: `run_checks` takes the lib folder as an argument
(SC2154, "lib is referenced but not assigned", a hidden coupling), `cd ... || exit` in `tests/run.sh` (SC2164),
a `source-path` directive for SC1091, and one `disable=SC2153` for the settings set by `printf -v`.

### 9. Install it on web-01 (twice)
Back in web-01 as asha, in `~/hc`:
```bash
sudo ./install.sh
```
```
created    user hc
installed  /opt/hc/bin/hc
...
installed  /etc/logrotate.d/hc
Created symlink /etc/systemd/system/timers.target.wants/hc.timer → /etc/systemd/system/hc.timer.
done: hc 1.0.0, timer enabled
```
Run it again. Every line says `unchanged`, and the config is `kept`. That is idempotent.
```bash
sudo ./install.sh
systemctl list-timers hc.timer
```
The next run is at the next five-minute mark.

### 10. The first real run
```bash
sudo systemctl start hc
journalctl -u hc -n 14
cat /var/log/hc/hc.log
```
Every check is OK, then `hc.service: Deactivated successfully.`, and the log has its first line:
```
2026-10-20T12:26:52+00:00 host=web-01 status=OK problems=""
```
Now try the guards:
```bash
hc
sudo hc
sudo hc -n | tail -n 3
```
```
hc: cannot read config /etc/hc/hc.conf
hc: not as root: use systemctl start hc, or --dry-run
dry run: would log: ... status=OK problems=""
...
```
As asha, `hc` cannot read the config (the webhook URL is a secret, mode 640). As root it refuses a real run.
The dry run line comes first because it goes to standard error, past the pipe.

### 11. Break it on purpose
Demo only: make the timer fire every 30 seconds.
```bash
sudo install -D -m 644 systemd/demo-30s.conf /etc/systemd/system/hc.timer.d/demo-30s.conf
sudo systemctl daemon-reload
systemctl list-timers hc.timer
```
**Stage one (staged): fill the data disk.**
```bash
df -h /data
sudo fallocate -l 44M /data/fill.bin
df -h /data
```
Use% goes from about 15% to 83%: over WARN (80), under CRIT (90). Within 30 seconds your `docker logs -f hooks`
terminal shows exactly one message:
```
12:28:00  POST /hc  web-01: OK -> WARN
          disk /data: 83% used
```
Wait a minute, then:
```bash
journalctl -u hc --since '-2min' | grep -E 'disk /data|alert'
cat /var/lib/hc/state
```
Every run sees `WARN  disk /data  83% used`, but only one `alert sent: OK -> WARN, HTTP 200`. The state file
says `WARN`, and the chat still has one message.

**Stage two (staged, worse): stop the API.**
```bash
sudo systemctl stop allcsvideos-api
```
Next run, the chat gets:
```
12:29:30  POST /hc  web-01: WARN -> CRIT
          disk /data: 83% used
          service allcsvideos-api: inactive
          api: unreachable: [Errno 111] Connection refused
```
```bash
journalctl -u hc -n 15
```
Two CRIT lines, `alert sent: WARN -> CRIT, HTTP 200`, and still `Deactivated successfully`: CRIT is a result,
not a failure of `hc`.

**Fix both:**
```bash
sudo systemctl start allcsvideos-api
sudo rm /data/fill.bin
```
Next run: `CRIT -> OK`, `all checks OK again`. The log tells the whole story:
```bash
tail -n 6 /var/log/hc/hc.log | cut -c 1-96
```
```
... status=OK problems=""
... status=WARN problems="disk /data 83% used"
... status=WARN problems="disk /data 83% used"
... status=WARN problems="disk /data 83% used"
... status=CRIT problems="disk /data 83% used;service allcsvid
... status=OK problems=""
```

### 12. Demo over: back to every 5 minutes
```bash
sudo rm -r /etc/systemd/system/hc.timer.d
sudo systemctl daemon-reload
systemctl list-timers hc.timer
```

### 13. Log rotation
```bash
sudo logrotate -f /etc/logrotate.d/hc
ls -l /var/log/hc
sudo systemctl start hc
ls -l /var/log/hc
```
`hc.log` becomes `hc.log.1`, a new empty `hc.log` appears, and the next run writes straight into it
(60 bytes). No signal needed.

### At real scale
For fifty servers: each server exposes metrics and Prometheus collects them, Alertmanager groups, silences and
routes alerts (Module 16), and Ansible rolls the files out to the fleet (Module 12).
Extensions to try yourself: a certificate-expiry check, a heartbeat so you notice when `hc` itself stops,
and a repeat alert when a CRIT lasts longer than an hour.

## Common mistakes
- Reading the config with `source`: then any line in the file runs as code. Read it as data.
- Mixing up exit codes: in the earlier scripts `2` meant a usage error. Here `2` means CRIT and `3` is UNKNOWN.
- Alerting on every run: the same message every five minutes is how people learn to ignore alerts.
- Saving the new state before the alert went out: if the chat is down, the alert is lost. Save it only after.
- Treating WARN/CRIT as a service failure: without `SuccessExitStatus=1 2`, a failed unit would no longer mean
  "hc itself is broken".
- Looking only at free memory (it looks scary on every healthy Linux server) instead of `MemAvailable`; or only
  at disk space, when a disk can run out of inodes first.
- Running `hc` by hand as root for real: use `sudo systemctl start hc`, or `sudo hc -n` to just look.
- Forgetting to remove the 30-second demo drop-in.

## Clean up
Leave web-01 (`exit`), then on your laptop:
```bash
bash lab/down.sh
```
This removes the `web-01` and `hooks` containers, the `hc-lab` network and the `hc-lab-web01` image.
The pulled `ubuntu:24.04`, `python:3.13.16-slim` and `koalaman/shellcheck:v0.11.0` images stay (other lessons
use them); remove them with `docker image rm` if you want.

## Next
Module 4, Lesson 1: IP Addresses, Subnets and CIDR -> [../../networking/m04-l01-ip-addresses-subnets-and-cidr](../../networking/m04-l01-ip-addresses-subnets-and-cidr)
