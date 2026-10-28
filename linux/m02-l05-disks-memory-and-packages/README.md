# M02-L05 · Disks, Memory and Packages
> Video: Module 2, Lesson 5. Watch it first, then follow along here.

## What you'll learn
- How disks, partitions, filesystems and mount points fit together, and how to read them with `lsblk`, `df`, `mount` and `/etc/fstab`
- How to handle "No space left on device": `df` to find the full filesystem, `du` and `find` to find what filled it, `lsof +L1` when `df` and `du` disagree
- Why deleting a log that a process still has open frees nothing, and why `truncate` and `gzip` are the safe ways to free space
- How to read memory: `free -h` (watch **available**, not free), swap, `vmstat`, `ps` sorted by memory, and the OOM killer
- How to manage software with `apt` and `dpkg`: update, upgrade, search, show, install, remove, purge and hold

## Before you start
- Docker Desktop (or Docker Engine) running on your laptop. The whole lesson runs in Ubuntu 24.04 containers.
- About 3 GB of free disk space (the memory demo writes a 2 GB file for a moment) and an internet connection (apt downloads packages).
- You only need this folder. The story continues from M02-L03 (the API, the HUP signal) and M02-L04.
- The full disk is **staged** on purpose: when web-01 starts, it fills its small data disk before you log in.
- In this lab, asha's sudo password is the fake demo value `demo-password-123`.

## Files in this folder
| File | What it is |
|---|---|
| `lab/Dockerfile` | Builds "web-01" from `ubuntu:24.04`: sudo, lsof, curl, python3, nginx pinned to `1.24.0-2ubuntu7`, users `asha` and `allcs` |
| `lab/start.sh` | Runs when the container starts: fills `/data` (uploads, an old log, a debug log until the disk is full) and starts the API |
| `lab/files/api.py` | The allcsvideos API stand-in on port 8080: `POST /upload`, a chatty debug log when `LOG_LEVEL=debug`, reloads settings and reopens logs on `SIGHUP` |
| `lab/files/gen_fill.py` | Writes realistic log lines up to a size, or until the disk is full |
| `lab/files/data.fstab` | A one-line fstab for the data disk, put in asha's home folder for the `findmnt --verify` step |
| `lab/up.sh` | Builds the image and starts `web-01` with a 64 MB, 4096-inode tmpfs at `/data` |
| `lab/stage.sh` | The two staged moments: `burst` (debug log grows by 20 MB) and `inodes` (inodes run out) |
| `lab/down.sh` | Removes the containers and the image |

## Follow along

### 1. Start web-01 and log in
```bash
./lab/up.sh
docker exec -it web-01 su - asha
```

### 2. The upload that fails
```bash
curl -s --data-binary @/tmp/lesson-05.mp4 'localhost:8080/upload?name=lesson-05.mp4'
```
```
{"error": "upload failed: No space left on device", "file": "lesson-05.mp4"}
```

### 3. Disks, filesystems and mounts
```bash
lsblk -e 1,43
df -h
df -hT / /data
mount | grep ' /data '
cat /etc/fstab
cat data.fstab
findmnt --verify --tab-file data.fstab
df -i / /data
```
```
Filesystem     Type     Size  Used Avail Use% Mounted on
overlay        overlay  911G   20G  845G   3% /
tmpfs          tmpfs     64M   64M     0 100% /data
...
tmpfs on /data type tmpfs (rw,nosuid,nodev,noexec,relatime,size=65536k,nr_inodes=4096,mode=755)
...
Success, no errors or warnings detected
```
Your disk names and sizes for `/` will differ: they belong to Docker's virtual machine. `/data` should match. In this lab the data disk is a tmpfs (kept in memory) so it can be filled safely; on a real server it would be ext4 or xfs on its own disk. Mounting by hand needs root and privileges the container does not have, so here you only read mounts.

### 4. Find what filled the disk
```bash
df -h /data
du -sh /data/*
cd /data
du -h --max-depth=1 | sort -h
ls -lh logs
find /data -type f -size +10M -exec ls -lh {} +
```
```
-rw-r----- 1 allcs adm  39M Oct 20 10:25 api-debug.log
-rw-r----- 1 allcs adm 301K Oct 20 10:25 api.log
-rw-r----- 1 allcs adm  17M Oct 18 23:59 api.log.1
```

### 5. The trap: deleting an open file
```bash
sudo rm /data/logs/api-debug.log
df -h /data          # still 100%
du -sh /data         # only about 26M
sudo lsof +L1
```
```
COMMAND  PID  USER   FD   TYPE DEVICE SIZE/OFF NLINK NODE NAME
python3 3031 allcs    4w   REG  0,136 40579072     0    9 /data/logs/api-debug.log (deleted)
```
The API still holds the deleted file open. It reopens its logs on HUP. Your PID will be different, so look it up:
```bash
PID=$(pgrep -x python3)
sudo kill -HUP $PID
df -h /data
sudo lsof +L1        # prints nothing now
ls -lh logs          # a fresh api-debug.log is already growing
```
```
tmpfs            64M   26M   39M  40% /data
```

### 6. Free space safely
Compress the old rotated log (nothing has it open):
```bash
sudo gzip logs/api.log.1
ls -lh logs
df -h /data
```
Now make the debug log grow again. In a **second terminal on your laptop** (not inside the container), run:
```bash
./lab/stage.sh burst
```
Back in asha's shell, empty the file in place instead of deleting it:
```bash
ls -lh logs/api-debug.log
df -h /data
sudo truncate -s 0 logs/api-debug.log
df -h /data
ls -lh logs/api-debug.log
ls -lh logs/api-debug.log
sudo lsof +L1
```
The name stays, the API keeps writing to the same file, and the blocks are freed at once.

### 7. Fix the cause and retry the upload
```bash
grep -n -B1 LOG_LEVEL /srv/allcsvideos/app.env
sudo sed -i 's/^LOG_LEVEL=debug/LOG_LEVEL=info/' /srv/allcsvideos/app.env
sudo kill -HUP $PID
tail -n 1 logs/api.log
cd
curl -s --data-binary @/tmp/lesson-05.mp4 'localhost:8080/upload?name=lesson-05.mp4'
df -h /data
```
```
... INFO SIGHUP: reloaded settings, reopened logs (LOG_LEVEL=info)
{"saved": "lesson-05.mp4", "bytes": 6291456}
```
Prevention, part one: logrotate. nginx already ships a rule (daily, keep 14, compress):
```bash
cat /etc/logrotate.d/nginx
```

### 8. Memory
```bash
free -h
dd if=/dev/zero of=/var/tmp/big.img bs=1M count=2048
free -h              # free drops, buff/cache grows, available stays about the same
rm /var/tmp/big.img
free -h
swapon --show
vmstat 1 5
ps -eo pid,user,rss,comm --sort=-rss | head -n 5
cat /proc/$PID/oom_score /proc/$PID/oom_score_adj
```
Your totals depend on how much memory Docker Desktop gives its VM.

### 9. The OOM killer, in a throwaway box
In a terminal on your laptop, start a separate test box with a hard 200 MB limit and no swap:
```bash
docker run -it --rm --name test-01 --hostname test-01 --memory 200m --memory-swap 200m ubuntu:24.04 bash
```
Inside it:
```bash
cat /sys/fs/cgroup/memory.max
tail /dev/zero
echo $?
grep oom /sys/fs/cgroup/memory.events
exit
```
```
209715200
Killed
137
oom 1
oom_kill 1
```
Exit code 137 is 128 + 9, the KILL signal. On a normal server, `dmesg` or `journalctl -k` names the killed process.

### 10. Packages with apt and dpkg
Back in asha's shell on web-01. The package lists start empty, as on a fresh Ubuntu image:
```bash
sudo apt install ncdu                         # E: Unable to locate package ncdu
cat /etc/apt/sources.list.d/ubuntu.sources
sudo apt update
apt list --upgradable
apt search ncdu
apt show ncdu
sudo apt install ncdu
dpkg -l ncdu
which ncdu
dpkg -L ncdu
dpkg -S /usr/bin/du
ncdu /data                                    # arrow keys move, Enter opens, q quits
```
On an Intel/AMD laptop the archive is `archive.ubuntu.com` / `security.ubuntu.com` instead of `ports.ubuntu.com`, and the architecture is `amd64` instead of `arm64`. The list of upgradable packages and their versions will be newer than in the video.

Remove versus purge:
```bash
sudo apt install -y screen
sudo apt remove -y screen
dpkg -l screen | tail -n 1                    # rc: removed, config files remain
ls -l /etc/screenrc
sudo apt purge -y screen
dpkg -l screen | tail -n 1                    # no packages found
ls -l /etc/screenrc
```
Hold a package:
```bash
apt-cache policy nginx
sudo apt-mark hold nginx nginx-common
apt-mark showhold
sudo apt upgrade                              # nginx and nginx-common are kept back
apt list --upgradable | wc -l                 # apt warns: no stable CLI for scripts
```
When you are ready to let nginx update: `sudo apt-mark unhold nginx nginx-common`. To install an exact version, put it after `=`, as the Dockerfile does: `apt install nginx=1.24.0-2ubuntu7`.

Optional: see the two settings that switch on automatic security updates:
```bash
sudo apt-get install -y unattended-upgrades
cat /etc/apt/apt.conf.d/20auto-upgrades
```
```
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```

### 11. Pitfall: running out of inodes
From your laptop terminal:
```bash
./lab/stage.sh inodes
```
Then in asha's shell:
```bash
sudo touch /data/uploads/test.txt             # No space left on device
df -h /data                                   # but only 27% used
df -i /data                                   # 100% of inodes used
sudo find /data/cache -type f | wc -l
sudo rm -r /data/cache
df -i /data
```

## Common mistakes
- **Running out of inodes.** "No space left on device" while `df -h` shows free space: check `df -i`.
- **`du` and `df` disagree.** Almost always a deleted file still held open. Run `lsof +L1`, then restart or reload the process. Next time, `truncate` instead of deleting.
- **Panicking about low free memory.** Read **available**, not free. Linux fills spare memory with cache on purpose.
- **`apt` in scripts.** `apt` is built for people and warns it has no stable command-line interface. In scripts, use `apt-get -y`.
- **A typo in fstab** can stop a server from booting. Run `findmnt --verify` before a reboot, and use `nofail` for extra disks.

## Clean up
```bash
./lab/down.sh
```
This removes `web-01` (and its `/data` disk), `test-01` if it is still running, and the `disk-lab:1` image. Your laptop may keep the downloaded `ubuntu:24.04` image; remove it with `docker rmi ubuntu:24.04` only if no other lesson needs it.

## Next
M02-L06 · SSH and Remote Servers: [../m02-l06-ssh-and-remote-servers](../m02-l06-ssh-and-remote-servers)
