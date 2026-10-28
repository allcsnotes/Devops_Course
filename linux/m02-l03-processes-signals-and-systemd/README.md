# M02-L03 · Processes, Signals and systemd
> Video: Module 2, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- Program vs process, PID and PPID, the process tree with PID 1 (systemd) at the top, fork and exec
- Process states (R, S, D, T, Z), zombies and orphans, and shell jobs (`&`, Ctrl+Z, `bg`, `fg`)
- Reading `ps aux`, `ps -ef --forest`, `pstree`, `uptime` and `top` to find what is eating a CPU
- Signals: TERM first, KILL only if needed, and why (`kill`, `pkill`, `trap`)
- systemd: `systemctl status/start/stop/restart/reload/enable`, writing your own unit file with `Restart=on-failure`
- Reading service logs with `journalctl` (`-u`, `-f`, `--since`, `-n`, `-p`)

## Before you start
- Docker Desktop and a terminal on your laptop (from M01-L03).
- Recorded on `ubuntu:24.04` (Ubuntu 24.04.5 LTS) with systemd 255.4, procps 4.0.4, psmisc 23.7, nginx 1.24.0, Python 3.12.3.
- Helpful: M02-L01 (`/proc`, symlinks, `tail -f`) and M02-L02 (`sudo`, users).
- PIDs, times, load and CPU numbers will differ on your machine. Use the PIDs **your** commands print.

This lab runs **systemd as PID 1** inside the container, like a real server. That needs a container started in the
background with `--privileged`, so instead of a one-line `docker run -it` you start it with `docker run -d` and then
open shells into it with `docker exec`. Only use `--privileged` for throwaway lab containers like this one.

**Lab password is fake.** Asha's password inside the lab is `demo-password-123`. It exists only in this container.

## Files in this folder
| File | What it is |
|------|------------|
| `lab/Dockerfile` | Builds "web-01": Ubuntu 24.04 + systemd, dbus, procps, psmisc, sudo, nginx, python3, curl, cron, less, nano; runs `/sbin/init` |
| `lab/setup-root.sh` | Runs at build time: users `asha` (groups `sudo`, `adm`) and `priya`, installs the API and Asha's demo scripts |
| `lab/files/api.py` | The allcsvideos API stand-in on port 8080 (`/health`, `/courses`). It has a staged bug: `/reindex` loops forever |
| `lab/files/worker.sh` | Demo upload worker: holds a lock file and removes it when it gets SIGTERM (installed as `~asha/worker.sh`) |
| `lab/files/zombie.py` | Makes a zombie on purpose: the child exits, the parent never collects it (installed as `~asha/zombie.py`) |
| `lab/files/allcsvideos-api.service` | The finished unit file from the lesson, for reference (you type it yourself in step 9) |

## Follow along

### 1. Start web-01
From this folder on your laptop:
```bash
docker build -t linux-lab:m02-l03 lab/
docker run -d --rm --name linux-lab --hostname web-01 --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock linux-lab:m02-l03
```

### 2. Stage the incident
Priya starts the API by hand with `nohup` and logs out:
```bash
docker exec -it linux-lab su - priya
```
```bash
nohup python3 /opt/allcsvideos/api.py > api.log 2>&1 &
exit
```
Check it from your laptop, then send the one request that triggers the staged bug:
```bash
docker exec linux-lab curl -s localhost:8080/courses
docker exec linux-lab curl -s -m 1 localhost:8080/reindex
```
The first prints `{"courses": 3}`. The second times out, and the API is now stuck in a loop.

Now open Asha's shell. Keep it open for the rest of the lesson:
```bash
docker exec -it linux-lab su - asha
```
```bash
curl -m 5 localhost:8080/courses
```
```
curl: (28) Operation timed out after 5007 milliseconds with 0 bytes received
```

### 3. Find processes with ps and pstree
```bash
ps
echo $$
ps -o pid,ppid,user,cmd
ps aux
ps -ef --forest
pstree -p
ps -p 1 -o pid,ppid,user,cmd
ls -l /sbin/init
```
In `ps aux` one line stands out: `priya ... R ... python3 /opt/allcsvideos/api.py` with a high `%CPU`.
In `ps -ef --forest` its parent (PPID) is `1`: no shell owns it any more. And:
```
      1       0 root     /sbin/init
lrwxrwxrwx 1 root root 22 ... /sbin/init -> ../lib/systemd/systemd
```

### 4. Jobs in your own shell
```bash
sleep 300 &
jobs
sleep 600
```
Press **Ctrl+Z** to pause `sleep 600`. Then:
```bash
jobs -l
ps -o pid,ppid,stat,cmd
bg %2
jobs
fg %1
```
Press **Ctrl+C** to stop `sleep 300`. Then:
```bash
jobs
kill %2
jobs
```
`ps` shows the background sleep as `S`, the paused one as `T`, and the last `jobs` says `Terminated`.

### 5. A zombie and an orphan
```bash
python3 zombie.py &
ps -o pid,ppid,stat,cmd
```
```
    881     261 S    python3 zombie.py
    882     881 Z    [python3] <defunct>
```
Use **your** PIDs: first try to kill the zombie, then end its parent.
```bash
kill -9 <zombie-pid>
ps -o pid,ppid,stat,cmd
kill <parent-pid>
ps -o pid,ppid,stat,cmd
```
`kill -9` changes nothing. Killing the parent removes the zombie too. Now an orphan:
```bash
bash -c 'sleep 500 &'
ps -o pid,ppid,stat,cmd -C sleep
```
The sleep's PPID is `1`: PID 1 adopted it.

### 6. How busy is the server?
```bash
uptime
nproc
top -bn1 | head -15
pgrep -a python3
ps -o pid,ppid,user,stat,etime,%cpu,cmd -p <api-pid>
```
`top` lists the API first, user `priya`, state `R`, near 90-100% of one CPU. In live `top`: `P` sorts by CPU,
`M` by memory, `k` kills, `q` quits.

### 7. Signals: TERM first
```bash
kill -l
./worker.sh &
cat /tmp/upload-worker.lock
kill <worker-pid>
ls /tmp/upload-worker.lock
```
```
worker: got SIGTERM, removing the lock file
ls: cannot access '/tmp/upload-worker.lock': No such file or directory
```
Now the same with KILL:
```bash
./worker.sh &
kill -9 <worker-pid>
ls /tmp/upload-worker.lock
./worker.sh
rm /tmp/upload-worker.lock
```
```
/tmp/upload-worker.lock
worker: lock file exists, is another worker running? exiting
```
Signal by name (this ends the orphaned `sleep 500`):
```bash
pgrep -a sleep
pkill sleep
pgrep -a sleep
```
Now stop the stuck API (it belongs to priya, so you need sudo; password `demo-password-123`):
```bash
kill <api-pid>
sudo kill <api-pid>
ps -p <api-pid>
curl localhost:8080/courses
```
```
-bash: kill: (186) - Operation not permitted
curl: (7) Failed to connect to localhost port 8080 after 0 ms: Couldn't connect to server
```

### 8. systemd and systemctl
```bash
export SYSTEMD_PAGER=
systemctl status nginx
systemctl is-active nginx
systemctl is-enabled nginx
systemctl is-active allcsvideos-api
```
```
     Active: active (running) since ...
active
enabled
inactive
```
Reload vs restart (watch the PIDs):
```bash
ps -o pid,ppid,cmd -C nginx | head -3
sudo systemctl reload nginx
ps -o pid,ppid,cmd -C nginx | head -3
sudo systemctl restart nginx
ps -o pid,ppid,cmd -C nginx | head -3
```
After `reload` the master PID stays and the workers are new. After `restart` the master is new too.
```bash
systemctl list-units --type=service --state=running
systemctl cat nginx
```

### 9. A unit file for the API
```bash
sudo useradd --system --shell /usr/sbin/nologin allcs
id allcs
sudo nano /etc/systemd/system/allcsvideos-api.service
```
Type this (same as `lab/files/allcsvideos-api.service`), then **Ctrl+O**, Enter, **Ctrl+X**:
```ini
[Unit]
Description=allcsvideos API
After=network.target

[Service]
User=allcs
ExecStart=/usr/bin/python3 /opt/allcsvideos/api.py
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
```
Prefer to copy it? From your laptop: `docker cp lab/files/allcsvideos-api.service linux-lab:/etc/systemd/system/`
```bash
cat /etc/systemd/system/allcsvideos-api.service
sudo systemctl daemon-reload
sudo systemctl enable --now allcsvideos-api
systemctl status allcsvideos-api
curl localhost:8080/courses
```
```
Created symlink /etc/systemd/system/multi-user.target.wants/allcsvideos-api.service → /etc/systemd/system/allcsvideos-api.service.
     Active: active (running) since ...
... python3[2955]: allcsvideos-api: listening on port 8080
{"courses": 3}
```

### 10. Prove Restart=on-failure
```bash
systemctl show -p MainPID allcsvideos-api
sudo kill -9 <main-pid>
systemctl is-active allcsvideos-api
sleep 3
systemctl status allcsvideos-api
```
Right after the kill it says `activating`; then `active (running)` with a new Main PID and `Scheduled restart job`.
A plain TERM is a clean stop, so it stays down:
```bash
sudo kill <new-main-pid>
systemctl is-active allcsvideos-api
sudo systemctl start allcsvideos-api
systemctl is-active allcsvideos-api
```
```
inactive
active
```
The everyday commands, and enable vs start:
```bash
sudo systemctl stop allcsvideos-api
systemctl is-active allcsvideos-api
sudo systemctl start allcsvideos-api
sudo systemctl restart allcsvideos-api
systemctl is-active allcsvideos-api
sudo systemctl disable allcsvideos-api
systemctl is-enabled allcsvideos-api
systemctl is-active allcsvideos-api
sudo systemctl enable allcsvideos-api
```
After `disable`: `is-enabled` says `disabled`, but `is-active` still says `active`.

### 11. journalctl
```bash
journalctl -u allcsvideos-api
```
You see the start, `listening on port 8080`, your `kill -9` (`code=killed, status=9/KILL`), the scheduled
restart, and `Deactivated successfully` after the TERM. Follow it live:
```bash
journalctl -u allcsvideos-api -f
```
In a **second laptop terminal**, send three requests, then press **Ctrl+C** in the first:
```bash
docker exec linux-lab curl -s localhost:8080/courses
docker exec linux-lab curl -s localhost:8080/health
docker exec linux-lab curl -s localhost:8080/courses
```
```bash
journalctl -u allcsvideos-api --since "1 min ago"
```

### 12. A staged failure: port already in use
As Asha, stop the service:
```bash
sudo systemctl stop allcsvideos-api
```
In the second laptop terminal, Priya starts a copy by hand again:
```bash
docker exec -it linux-lab su - priya
```
```bash
nohup python3 /opt/allcsvideos/api.py > api.log 2>&1 &
exit
```
Back as Asha:
```bash
sudo systemctl start allcsvideos-api
systemctl status allcsvideos-api
journalctl -u allcsvideos-api -n 12
journalctl -p err
journalctl -u allcsvideos-api -p warning -n 6
```
```
     Active: activating (auto-restart) (Result: exit-code) since ...
... OSError: [Errno 98] Address already in use
-- No entries --
... allcsvideos-api.service: Failed with result 'exit-code'.
```
Find who holds the port and stop it:
```bash
pgrep -a -u priya python3
sudo kill <priya-api-pid>
systemctl status allcsvideos-api
curl localhost:8080/health
```
systemd kept retrying, so a few seconds later it is `active (running)` and `/health` says `ok`.

### 13. Pitfalls, tried out
Editing a unit and forgetting `daemon-reload`:
```bash
sudo sed -i 's/RestartSec=2/RestartSec=5/' /etc/systemd/system/allcsvideos-api.service
sudo systemctl restart allcsvideos-api
sudo systemctl daemon-reload
sudo systemctl restart allcsvideos-api
```
```
Warning: The unit file, source configuration file or drop-ins of allcsvideos-api.service changed on
disk. Run 'systemctl daemon-reload' to reload units.
```
Running is not the same as working. Trigger the bug again from your laptop:
```bash
docker exec linux-lab curl -s -m 1 localhost:8080/reindex
```
Back as Asha:
```bash
systemctl is-active allcsvideos-api
curl -m 3 localhost:8080/health
ps -o pid,stat,%cpu,etime,cmd -u allcs
sudo systemctl restart allcsvideos-api
curl localhost:8080/health
```
`is-active` says `active` while `curl` times out and the API burns a CPU. A restart brings back `ok`.
How systemd stops a service:
```bash
systemctl show allcsvideos-api -p KillSignal -p TimeoutStopUSec -p Restart -p NRestarts
```
```
Restart=on-failure
TimeoutStopUSec=1min 30s
NRestarts=0
KillSignal=15
```

## Common mistakes
- **Forgetting `systemctl daemon-reload`** after editing a unit file. systemd keeps using the old version until you do.
- **Running is not working.** `Restart=on-failure` only helps when the process dies. A hung process needs a health check (module 3, and Kubernetes probes in module 14).
- **Reaching for `kill -9` first.** It skips every cleanup: lock files, half-written files, open connections. Send TERM, wait a few seconds, KILL only if it won't go.
- **Starting services by hand** with `nohup` and `&`. No restart, no start at boot, logs in a random file, and it runs as whoever typed it. Give it a unit file.
- **`pkill` matches every process with that name**, not just the one you meant.

## Clean up
Type `exit` in every `docker exec` shell. Then on your laptop:
```bash
docker stop linux-lab         # --rm removes the container once it stops
docker rmi linux-lab:m02-l03
```

## Next
M02-L04 · Text Processing: [../m02-l04-text-processing](../m02-l04-text-processing)
