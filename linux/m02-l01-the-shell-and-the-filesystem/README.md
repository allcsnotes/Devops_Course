# M02-L01 · The Shell and the Filesystem
> Video: Module 2, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- The difference between the terminal, the shell (bash) and the prompt, and how to read `asha@web-01:~$`
- How a command is built (command, options, arguments) and how bash finds programs on your `PATH`
- How to move around the one Linux directory tree with absolute and relative paths
- The folders a DevOps engineer visits most: `/etc`, `/var/log`, `/home`, `/usr/bin`, `/tmp`, `/proc`, `/dev`
- Creating, copying, moving, reading and deleting files, and why `rm -rf $DIR/*` is dangerous
- Hard links vs symbolic links, and how nginx turns sites on with a symlink

## Before you start
- Docker Desktop (from M01-L03) and a terminal on your laptop. Nothing else is needed: the lab is a container.
- The lesson was recorded on `ubuntu:24.04` (Ubuntu 24.04.5 LTS), bash 5.2.21, nginx 1.24.0, on an Apple-silicon Mac.
  On an Intel/AMD laptop a few outputs differ (for example `file` says `x86-64` instead of `ARM aarch64`),
  and numbers like inode numbers, PIDs, memory and CPU count will be different on your machine.

## Files in this folder
| File | What it is |
|------|------------|
| `lab/Dockerfile` | Builds "web-01": Ubuntu 24.04, unminimized (man pages), nginx, man-db, file, less, tmux, curl |
| `lab/setup-root.sh` | Runs at build time: creates user `asha` (in group `adm`), the site folder, and the allcsvideos site config (not enabled) |
| `lab/start.sh` | Runs when the container starts: starts nginx, then logs you in as `asha` |
| `lab/site/index.html` | The allcsvideos page nginx should serve |
| `lab/site/allcsvideos` | The nginx site config, copied to `/etc/nginx/sites-available/allcsvideos` |

## Follow along

### 1. Start web-01
From this folder on your laptop:
```bash
docker build -t linux-lab:m02-l01 lab/
docker run -it --rm --name linux-lab --hostname web-01 linux-lab:m02-l01
```
You land at Asha's prompt:
```
asha@web-01:~$
```
Some steps need root (Rahul's `#` prompt). Open a **second** laptop terminal for those:
```bash
docker exec -it linux-lab bash
```
```
root@web-01:/#
```

### 2. The shell and the prompt
```bash
echo $SHELL
bash --version | head -n 1
```
You should see `/bin/bash` and `GNU bash, version 5.2.21(1)-release ...`.

### 3. Anatomy of a command, PATH, relative paths
```bash
ls -l -h /usr/sbin/nginx
ls -lh /usr/sbin/nginx
ls -l --human-readable /usr/sbin/nginx
echo $PATH
which ls
nginxx
```
```
/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
/usr/bin/ls
-bash: nginxx: command not found
```
Relative paths (`..` is the parent folder):
```bash
cd /etc/nginx/sites-available
cd ../sites-enabled
pwd
cd
```

### 4. Where am I? Navigation
```bash
pwd
ls
ls -a
ls -la
ls -l /etc/nginx
ls -l /usr/sbin/nginx
ls -lh /usr/sbin/nginx
```
In `ls -l /etc/nginx` look for `nginx.conf` (1446 bytes) and the two folders `sites-available` and `sites-enabled`.
`ls -l` prints `1338416` for the nginx program, `ls -lh` prints `1.3M`.
```bash
cd /etc/nginx
pwd
cd sites-available
ls
cd ..
pwd
cd
pwd
cd -
cd ~
pwd
```
`ls` in `sites-available` shows `allcsvideos  default`. `cd -` prints `/etc/nginx`.

### 5. A tour of the tree
```bash
ls /
ls -l /
cat /etc/hostname
head -n 2 /etc/os-release
ls /etc | wc -l
ls /var/log
ls -l /var/log/nginx
ls /home
ls /usr/bin | wc -l
ls -ld /tmp
ls /dev
ls /proc
```
In `ls -l /` notice `bin -> usr/bin`, `lib -> usr/lib`, `sbin -> usr/sbin`. `/etc/hostname` says `web-01`,
`/home` holds `asha  ubuntu`, and `/tmp` is `drwxrwxrwt`.

### 6. Making, copying, moving and removing files
```bash
mkdir site/config
mkdir -p site/config
touch site/notes.txt
ls -l site
cp /etc/nginx/sites-available/allcsvideos site/config/
cp site site-backup
cp -r site site-backup
ls
mv site/notes.txt site/README.txt
mv site-backup /tmp/
ls
ls -R site
rm site/README.txt
rm /tmp/site-backup
rm -r /tmp/site-backup
ls -R site
```
You should see the two expected errors:
```
mkdir: cannot create directory 'site/config': No such file or directory
cp: -r not specified; omitting directory 'site'
rm: cannot remove '/tmp/site-backup': Is a directory
```

### 7. The most dangerous line, staged safely
`echo` in front means the command is only **printed**, never run. Type it exactly like this:
```bash
DIR=""
echo rm -rf $DIR/*
echo rm -rf "${DIR:?}"/*
```
```
rm -rf /bin /bin.usr-is-merged /boot /dev /etc /home /lib /media /mnt /opt /proc
 /root /run /sbin /sbin.usr-is-merged /srv /sys /tmp /usr /var
-bash: DIR: parameter null or not set
```

### 8. Reading files
First give the access log a few lines. In the **root** terminal:
```bash
: > /var/log/nginx/access.log; for p in / /courses /favicon.ico /; do curl -s -o /dev/null http://127.0.0.1$p; sleep 2; done
```
Back as Asha:
```bash
cat site/config/allcsvideos
head -n 5 /etc/nginx/nginx.conf
tail -n 3 /var/log/nginx/access.log
less /etc/nginx/nginx.conf
```
In `less`: Space forward, `b` back, type `/gzip` and Enter to search, `q` to quit.
Near the gzip settings you will find the important line `include /etc/nginx/sites-enabled/*;`.
```bash
file /etc/nginx/nginx.conf /usr/sbin/nginx /var/log/nginx
file /etc/nginx/sites-enabled/default
which nginx
which cd
type cd
type ls
type nginx
ls --help | head -n 4
man ls
tldr ls
```
```
/etc/nginx/sites-enabled/default: symbolic link to /etc/nginx/sites-available/default
cd is a shell builtin
ls is aliased to `ls --color=auto'
-bash: tldr: command not found
```
`man ls` opens the manual page (`q` quits). It works because the Dockerfile ran `unminimize`; on a plain
`ubuntu:24.04` container `man` only prints a "This system has been minimized" note.

### 9. Hard links and symbolic links
```bash
cd site
cp config/allcsvideos app.conf
ln app.conf app-hard.conf
ln -s app.conf app-link.conf
ls -li
```
`app.conf` and `app-hard.conf` share one inode number and show a link count of `2`.
`app-link.conf -> app.conf` has its own inode and is 8 bytes. Now break it:
```bash
rm app.conf
ls -l
head -n 2 app-hard.conf
cat app-link.conf
ln /etc/nginx nginx-hard
ls -l /etc/nginx/sites-enabled
cd
```
```
cat: app-link.conf: No such file or directory
ln: /etc/nginx: hard link not allowed for directory
lrwxrwxrwx 1 root root 34 ... default -> /etc/nginx/sites-available/default
```

### 10. Everything is a file
```bash
head -n 3 /proc/meminfo
cat /proc/loadavg
cat /proc/uptime
nproc
head -n 4 /proc/cpuinfo
ls -l /dev/null
echo "hello" > /dev/null
cat /dev/null
ls -l /proc/self
readlink /proc/self
readlink /proc/self
head -n 1 /proc/self/status
echo $$
ls -d /proc/[0-9]*
```
The two `readlink` lines print two different numbers, and `head -n 1 /proc/self/status` prints `Name:   head`.

### 11. Tab completion and history
Type `cd /etc/ng` and press **Tab**: bash completes `cd /etc/nginx/`. Add `s` and press **Tab twice**:
```
scgi_params      sites-available/ sites-enabled/   snippets/
```
Type `ites-e`, press **Tab** again, then Enter. Then:
```bash
ls
cd
history | tail -n 4
```
Press the **Up arrow** to bring back the last command. Press **Ctrl+R**, type `access`, and bash finds
`tail -n 3 /var/log/nginx/access.log`. Enter runs it.

### 12. Answer Rahul: diagnose and fix nginx
As Asha:
```bash
ls /etc/nginx/sites-available
ls -l /etc/nginx/sites-enabled
```
Only `default` is linked, so `allcsvideos` is never loaded. The fix needs root. In the **root** terminal:
```bash
ln -s /etc/nginx/sites-available/allcsvideos /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default
nginx -t
nginx -s reload
```
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```
Back as Asha:
```bash
ls -l /etc/nginx/sites-enabled
curl -s http://127.0.0.1/
```
```
allcsvideos -> /etc/nginx/sites-available/allcsvideos
<!doctype html>
<html><head><title>allcsvideos</title></head>
<body><h1>allcsvideos</h1><p>Video courses for engineers.</p></body></html>
```

### 13. Watch the requests come in
As Asha:
```bash
tail -f /var/log/nginx/access.log
```
In the **root** terminal, send a test request every two seconds:
```bash
for p in / /courses/devops / /index.html /; do curl -s -o /dev/null http://127.0.0.1$p; sleep 2; done
```
Each request appears as it happens. Old lines served `615` bytes (the nginx welcome page), new ones `138`
(the allcsvideos page), and `/courses/devops` gets a `404`. Press **Ctrl+C** to stop following.

### 14. Pitfalls, tried out
```bash
cd /Etc
ls /etc/Nginx
cd site
touch my notes
ls
touch "my notes"
ls
cd
```
```
-bash: cd: /Etc: No such file or directory
 app-hard.conf   app-link.conf   config   my  'my notes'   notes
```

## Common mistakes
- **`rm -rf $DIR/*` with an empty variable** becomes `rm -rf /*`. Use `"${DIR:?}"`, quote it, and put `echo` in front first.
- **Linux is case sensitive.** `/Etc` does not exist, and `nginx.conf` and `Nginx.conf` are two different files.
- **Spaces in names.** `touch my notes` makes two files. Quote names with spaces, and avoid them on servers.
- **Editing the wrong file.** A site in `sites-available` does nothing until it is linked into `sites-enabled`. Check with `ls -l` first.
- **Living at a `#` prompt.** Root gets no undo and no "are you sure". Work as a normal user and use admin rights only for the one command that needs them.

## Clean up
Type `exit` in both container terminals (the `--rm` flag removes the container when Asha's shell exits). Then on your laptop:
```bash
docker rm -f linux-lab        # only if it is still running
docker rmi linux-lab:m02-l01
```

## Next
M02-L02 · Users, Groups and Permissions: [../m02-l02-users-groups-and-permissions](../m02-l02-users-groups-and-permissions)
