# M03-L03 · Scheduling and Automation
> Video: Module 3, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- How cron reads its five time fields, and how to write and check a crontab line
- The classic cron traps: lost output, a tiny environment, `%` signs, and overlapping runs (fixed with `flock`)
- How a systemd timer starts a service on a calendar, with output and exit codes in the journal
- `Persistent=true` (catch up on missed runs) and `RandomizedDelaySec` (spread out the load)
- How logrotate keeps a fixed window of logs, and why the app must reopen its log (`postrotate` HUP or `copytruncate`)
- What actually runs logrotate every day on Ubuntu

## Before you start
- Docker Desktop (or Docker Engine on Linux) and a terminal with bash. On Windows, use WSL2 or Git Bash.
- The lab server needs a **privileged** container, because systemd runs as PID 1 inside it (the recipe from M02-L03).
  It was recorded on Docker Desktop (Apple silicon, linux/arm64); it works the same on x86_64.
- `morning-check.sh` is Asha's script from [M03-L02](../m03-l02-robust-scripts). A copy is in `bin/` here, so you need nothing else.
- The schedules fire in real time. Plan for some waiting: every-minute cron jobs and a 30-second timer.

Versions in the lab: `ubuntu:24.04` (Ubuntu 24.04.5 LTS), systemd 255.4, cron 3.0pl1, logrotate 3.21.0, util-linux 2.39.3 (`flock`).

## Files in this folder
| File | What it is |
|---|---|
| `bin/morning-check.sh` | Asha's morning check (from M03-L02): disks, nginx, 5xx errors. Exit code 1 when something needs a look |
| `bin/backup-uploads.sh` | A stand-in for a slow backup: it just takes 90 seconds |
| `units/morning-check.service` | The systemd service: `Type=oneshot`, runs the script as asha |
| `units/morning-check.timer.demo` | Demo timer: every 30 seconds, `AccuracySec=1s` |
| `units/morning-check.timer.persist` | Test timer for `Persistent=true` (you set the time with `sed`, step 17) |
| `units/morning-check.timer` | The real timer: every day at 07:00 Asia/Kolkata, `Persistent=true`, `RandomizedDelaySec=10min` |
| `logrotate/allcsvideos-api.v1` | First logrotate rule for the API log (no `postrotate` yet, on purpose) |
| `logrotate/allcsvideos-api.v2` | v1 plus a `postrotate` block that sends the API a HUP signal (the one Asha keeps) |
| `logrotate/allcsvideos-api.v3` | The `copytruncate` alternative, for comparison |
| `lab/Dockerfile` | The lab server image: `ubuntu:24.04` + systemd, cron, logrotate, nginx, python3 |
| `lab/up.sh`, `lab/down.sh` | Build and start the lab server `web-01`; remove it again |
| `lab/setup-root.sh` | Prepares web-01 (user asha, the API, a week-old 45 MB log, the nginx sample log). Run by `up.sh` |
| `lab/api.py`, `lab/allcsvideos-api.service` | A small stand-in for the allcsvideos API on port 8080 (reopens its log on SIGHUP) |
| `lab/gen_week.py`, `lab/gen_logs.py` | Generate the sample logs. Generated data, not real traffic |

## Follow along

### Start the lab

1. Build and start web-01, then log in as asha. `up.sh` copies this folder into web-01 as `/lesson`.
   ```bash
   ./lab/up.sh
   docker exec -it web-01 su - asha
   ```
   Every command below runs inside web-01 as asha. When `sudo` asks for a password, it is the fake lab password `demo-password-123`.

### The problem: nothing runs by itself

2. Run the morning check, look at the data disk, and check for a crontab.
   ```bash
   morning-check.sh
   ls -lh /data/logs
   head -n 1 /data/logs/api.log
   crontab -l
   ```
   You should see:
   ```
   WARN  disk /data is 83% full
   WARN  73 5xx errors in /var/log/nginx/access.log
   ...
   -rw-r----- 1 allcs adm 45M Oct 20 11:25 api.log
   2026-10-13T00:00:02 INFO GET /api/courses/205 200 76ms
   no crontab for asha
   ```
   (Your dates and times will be today's. The 45 MB log is staged: a week of generated lines, never rotated.)

### cron, hands-on

3. Turn off systemd's pager, check the clock, cron, and your PATH.
   ```bash
   export SYSTEMD_PAGER=
   date
   systemctl is-active cron
   echo $PATH
   ```
   The clock runs in UTC, cron is `active`, and PATH starts with `/home/asha/bin`.

4. Open your crontab. The first time, it shows a template full of comments. Add this line at the bottom, then save and exit (nano: Ctrl+O, Enter, Ctrl+X):
   ```bash
   crontab -e
   ```
   ```
   * * * * * morning-check.sh
   ```
   ```bash
   crontab -l | tail -n 2
   ```

5. Wait for the next minute, then look for a result.
   ```bash
   ls ~/logs
   journalctl -t CRON -n 4
   ```
   `~/logs` is empty. The journal shows the job ran, and that its output was thrown away:
   ```
   CRON[684]: (asha) CMD (morning-check.sh)
   CRON[683]: (CRON) info (No MTA installed, discarding output)
   ```

6. Fix number one: redirect output and errors to a log. Also dump cron's environment. Run `crontab -e` and replace your line with these two:
   ```
   * * * * * morning-check.sh >> /home/asha/logs/morning-check.log 2>&1
   * * * * * env > /tmp/cron-env.txt
   ```
   A minute later:
   ```bash
   cat ~/logs/morning-check.log
   cat /tmp/cron-env.txt
   ```
   ```
   /bin/sh: 1: morning-check.sh: not found
   HOME=/home/asha
   LOGNAME=asha
   PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
   LANG=C.UTF-8
   SHELL=/bin/sh
   PWD=/home/asha
   ```
   Cron's PATH has no `~/bin`, and the shell is `/bin/sh`.

7. Fix number two: full paths. Replace both lines in `crontab -e` with:
   ```
   * * * * * /home/asha/bin/morning-check.sh >> /home/asha/logs/morning-check.log 2>&1
   ```
   A minute later, `cat ~/logs/morning-check.log` shows the full report under the old error (no colours: there is no terminal).

8. The `%` trap. Replace the line with one that puts the date in the file name:
   ```
   * * * * * /home/asha/bin/morning-check.sh >> /home/asha/logs/check-$(date +%F).log 2>&1
   ```
   A minute later:
   ```bash
   ls ~/logs
   journalctl -t CRON -n 4
   ```
   No new file, and the command in the journal stops at `$(date +`. In a crontab, `%` means a new line.

9. Escape it with a backslash:
   ```
   * * * * * /home/asha/bin/morning-check.sh >> /home/asha/logs/check-$(date +\%F).log 2>&1
   ```
   A minute later:
   ```bash
   ls ~/logs
   cat ~/logs/check-*.log
   ```
   You should see a file like `check-2026-10-20.log` holding the report.

### System crontabs

10. Look at the system's own schedule files.
    ```bash
    cat /etc/crontab
    ls /etc/cron.d /etc/cron.daily
    cat /etc/cron.d/e2scrub_all
    ```
    System lines have a sixth field, the user (`root`). `cron.daily` holds plain scripts, including `logrotate`.

### Overlapping runs and flock

11. `backup-uploads.sh` is a stand-in that takes 90 seconds. Schedule it every minute (`crontab -e`, replace the line):
    ```bash
    cat ~/bin/backup-uploads.sh
    ```
    ```
    * * * * * /home/asha/bin/backup-uploads.sh >> /home/asha/logs/backup.log 2>&1
    ```
    After two or three minutes:
    ```bash
    cat ~/logs/backup.log
    pgrep -af backup-uploads
    ```
    ```
    11:32:01 backup started, PID 1811
    11:33:01 backup started, PID 1816
    11:33:31 backup finished, PID 1811
    ```
    A second backup started before the first one finished, and `pgrep` shows two copies running.

12. Stop them, clear the log, and add `flock -n` in front of the command:
    ```bash
    pkill -f backup-uploads.sh
    rm ~/logs/backup.log
    ```
    ```
    * * * * * flock -n /tmp/backup-uploads.lock /home/asha/bin/backup-uploads.sh >> /home/asha/logs/backup.log 2>&1
    ```
    After a few minutes, check again, and try the lock by hand while a backup runs:
    ```bash
    cat ~/logs/backup.log
    pgrep -af backup-uploads
    flock -n /tmp/backup-uploads.lock echo "got the lock"; echo $?
    ```
    Now it is started, finished, started: only one copy at a time. The manual `flock -n` gives up with exit code `1`.

13. Remove the whole crontab (no question, no undo: type `-r` carefully, it sits next to `-e`).
    ```bash
    crontab -r
    crontab -l
    ```
    Give the last backup up to 90 seconds to finish before you move on.

### systemd timers

14. Install the service and test it on its own first.
    ```bash
    sudo cp /lesson/units/morning-check.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl start morning-check.service
    echo $?
    systemctl status morning-check.service
    ```
    `Job for morning-check.service failed`, exit code `1`: the script found two problems, and systemd records any non-zero exit as a failure. `status` shows the script's own output, with timestamps, without any redirect.

15. Check calendar expressions before you use them.
    ```bash
    systemd-analyze calendar '*-*-* 07:00 Asia/Kolkata'
    systemd-analyze calendar 'Mon..Fri 09:00' '*:0/15'
    systemd-analyze calendar --iterations=3 '*:*:0/30'
    ```
    For 07:00 Asia/Kolkata, the next elapse is shown as `01:30:00 UTC`.

16. Install the demo timer (every 30 seconds), enable it, and watch it fire.
    ```bash
    sudo cp /lesson/units/morning-check.timer.demo /etc/systemd/system/morning-check.timer
    sudo systemctl daemon-reload
    sudo systemctl enable --now morning-check.timer
    systemctl list-timers morning-check.timer
    ```
    About a minute later:
    ```bash
    journalctl -u morning-check -n 30 | grep -E "Starting|finished"
    systemctl list-timers morning-check.timer
    ```
    You should see a run on the minute and on the half minute, each with its `finished` line.

17. Test `Persistent=true`. Stop the demo timer, set a test timer two minutes from now, start it, then stop it again ("the server is off"):
    ```bash
    sudo systemctl stop morning-check.timer
    T=$(date -d '+2 min' +%H:%M)
    sed "s/^OnCalendar=.*/OnCalendar=*-*-* $T:00/" /lesson/units/morning-check.timer.persist | sudo tee /etc/systemd/system/morning-check.timer
    sudo systemctl daemon-reload
    sudo systemctl start morning-check.timer
    systemctl list-timers morning-check.timer
    sudo systemctl stop morning-check.timer
    date
    ```
    Wait until the scheduled time has passed, then start the timer again:
    ```bash
    date
    sudo systemctl start morning-check.timer
    journalctl -u morning-check -n 30 | grep Starting | tail -n 2
    systemctl list-timers morning-check.timer
    ```
    The last `Starting` line is from the moment you started the timer: the missed run, caught up.

18. Install the real timer and list every timer on the server.
    ```bash
    sudo cp /lesson/units/morning-check.timer /etc/systemd/system/morning-check.timer
    sudo systemctl daemon-reload
    sudo systemctl restart morning-check.timer
    systemctl list-timers
    systemctl --failed
    ```
    `morning-check.timer` is due tomorrow just after 01:30 UTC (the random delay is already picked), and `logrotate.timer` at midnight. `--failed` lists the last failed check.

### Log rotation

19. Read the main config, then add Asha's rule (v1).
    ```bash
    grep -v "^#" /etc/logrotate.conf | grep -v "^$"
    ls /etc/logrotate.d
    sudo cp /lesson/logrotate/allcsvideos-api.v1 /etc/logrotate.d/allcsvideos-api
    sudo logrotate -d /etc/logrotate.d/allcsvideos-api
    ```
    The debug run changes nothing and ends with `log does not need rotating`: the first time logrotate meets a log, it records "now" as the last rotation.

20. Force a rotation, then send one request to the API.
    ```bash
    sudo logrotate -f /etc/logrotate.d/allcsvideos-api
    ls -l /data/logs
    curl -s localhost:8080/courses
    ls -l /data/logs
    ```
    ```
    -rw-r----- 1 allcs adm        0 Oct 20 11:42 api.log
    -rw-r----- 1 allcs adm 46137485 Oct 20 11:42 api.log.1
    ```
    `api.log` stays at 0 bytes and `api.log.1` grows: the API still writes to the renamed file.

21. Switch to v2 (with `postrotate`), send one HUP by hand to fix the current state, then force a rotation with the full rule.
    ```bash
    sudo cp /lesson/logrotate/allcsvideos-api.v2 /etc/logrotate.d/allcsvideos-api
    sudo systemctl kill --signal=HUP allcsvideos-api
    curl -s localhost:8080/courses
    ls -l /data/logs
    sudo logrotate -f /etc/logrotate.d/allcsvideos-api
    ls -l /data/logs
    cat /data/logs/api.log
    df -h /data
    ```
    ```
    -rw-r----- 1 allcs adm      83 Oct 20 11:42 api.log
    -rw-r----- 1 allcs adm     121 Oct 20 11:42 api.log.1
    -rw-r----- 1 allcs adm 5078241 Oct 20 11:42 api.log.2.gz
    2026-10-20T11:42:37 INFO SIGHUP: reloaded settings, reopened logs (LOG_LEVEL=info)
    tmpfs            64M   14M   51M  22% /data
    ```
    The 45 MB log is now 4.8 MB compressed, and the data disk dropped from 83% to 22%.

22. For comparison, try the `copytruncate` version (v3), then go back to v2.
    ```bash
    sudo cp /lesson/logrotate/allcsvideos-api.v3 /etc/logrotate.d/allcsvideos-api
    curl -s localhost:8080/courses
    sudo logrotate -f /etc/logrotate.d/allcsvideos-api
    ls -l /data/logs
    curl -s localhost:8080/courses
    ls -l /data/logs
    sudo cp /lesson/logrotate/allcsvideos-api.v2 /etc/logrotate.d/allcsvideos-api
    ```
    `api.log` is emptied in place, and the next request lands in it without any signal.

23. What runs logrotate every day?
    ```bash
    systemctl list-timers logrotate.timer
    systemctl cat logrotate.timer
    head -n 6 /etc/cron.daily/logrotate
    sudo systemctl start logrotate.service
    journalctl -u logrotate -n 3
    ls -l /var/lib/logrotate/status
    sudo grep data /var/lib/logrotate/status
    ```
    `logrotate.timer` (`OnCalendar=daily`, `Persistent=true`) does the job; the cron.daily script exits when systemd is running. The state file is root-only, so plain `grep` gets `Permission denied`; use `sudo`.

### Run the whole setup

24. Check the rule and the timers, then start the check exactly as the timer will.
    ```bash
    cat /etc/logrotate.d/allcsvideos-api
    systemctl list-timers morning-check.timer logrotate.timer
    sudo systemctl start morning-check.service
    journalctl -u morning-check -n 9
    ```
    ```
    morning-check.sh[3931]: OK    disk /data is 22% full
    morning-check.sh[3931]: WARN  73 5xx errors in /var/log/nginx/access.log
    systemd[1]: morning-check.service: Failed with result 'exit-code'.
    ```
    The disk is fine now. The 5xx warning stays (last week's errors are still in nginx's log), so the unit is honestly marked failed.

### The pitfalls, live

25. Time zones, `run-parts` names, and enabling the wrong unit.
    ```bash
    date
    TZ=Asia/Kolkata date
    sudo cp ~/bin/morning-check.sh /etc/cron.daily/
    run-parts --test /etc/cron.daily
    sudo mv /etc/cron.daily/morning-check.sh /etc/cron.daily/morning-check
    run-parts --test /etc/cron.daily
    sudo rm /etc/cron.daily/morning-check
    sudo systemctl enable morning-check.service
    ```
    Mumbai is 5.5 hours ahead of the server's UTC. `run-parts` skips `morning-check.sh` (a name with a dot) and lists it once renamed. Enabling the service prints a long "no installation config" warning: you enable the timer, not the service.

## Common mistakes
- **Cron's environment.** No login profile, plain `/bin/sh`, its own PATH. Use full paths, set variables inside the script, and when in doubt dump `env` from a cron job and compare.
- **Output going nowhere.** Without a mail system, cron discards output. Append `>> logfile 2>&1`.
- **Percent signs.** In a crontab, `%` means a new line. Escape every one as `\%`, or move the command into a script.
- **Time zones.** The server runs in UTC: `0 7 * * *` is 12:30 in Mumbai. Write `30 1 * * *`, or use a timer with a time zone (`OnCalendar=*-*-* 07:00 Asia/Kolkata`).
- **Overlapping runs.** Cron starts the next run even if the last one is still going. Wrap long jobs in `flock -n`. (A systemd service never starts a second copy while one is running.)
- **File names in cron.daily.** `run-parts` skips names with a dot, so `morning-check.sh` never runs. Drop the `.sh`.
- **Enabling the service instead of the timer.** Enable the timer; the timer starts the service.
- **Day of month and day of week together.** `0 9 1 * 1` runs on every 1st **and** every Monday, not "the 1st if it is a Monday".
- **`crontab -r`** deletes the whole crontab with no question. It sits right next to `-e`.
- **Renaming a log does not close it.** Without a `postrotate` HUP (or `copytruncate`), the app keeps writing to `api.log.1`.

## Clean up
Inside web-01 (optional, the container goes away anyway):
```bash
sudo systemctl disable --now morning-check.timer
exit
```
On your laptop:
```bash
./lab/down.sh
```
This removes the `web-01` container and the `web01-systemd` image. Nothing else was created.

## Next
[M03-L04 · Python for Ops](../m03-l04-python-for-ops)
