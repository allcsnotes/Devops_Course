# M02-L02 · Users, Groups and Permissions
> Video: Module 2, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- Who's who on a server: users, UIDs, groups, `/etc/passwd`, `/etc/shadow`, system users vs human users
- How the kernel checks access: owner, group, other, and the nine `rwx` bits, in letters and numbers (755, 640)
- `chmod`, `chown`, and what `r`, `w` and `x` really mean on a folder
- `sudo`, the sudoers file, and a narrow rule written safely with `visudo`
- `umask`, and the special bits: setuid, sticky and setgid
- Why `chmod 777` is never the fix, and what the real fix for an upload folder is

## Before you start
- Docker Desktop and a terminal on your laptop (from M01-L03). The lab is a container, nothing is installed on your laptop.
- Recorded on `ubuntu:24.04` (Ubuntu 24.04.5 LTS) with sudo 1.9.15p5, adduser 3.137ubuntu1, acl 2.3.2, nginx 1.24.0, nano 7.2.
- Helpful: M02-L01 (the shell, `ls -l`, links). Dates, inode numbers, PIDs and the number of nginx workers will differ on your machine.

**Lab passwords are fake.** Asha's password in the lab is `demo-password-123`, and you will give Priya
`demo-password-456`. They exist only inside this throwaway container. Never reuse them anywhere real.

## Files in this folder
| File | What it is |
|------|------------|
| `lab/Dockerfile` | Builds "web-01": Ubuntu 24.04 with sudo, adduser, acl, nginx, nano |
| `lab/setup-root.sh` | Runs at build time: user `asha` (groups `sudo`, `adm`), `/srv/allcsvideos` with `deploy.sh` and `app.env`, the root-owned uploads folder with three fake videos, a backup copy, and Meera's new upload in `/tmp` |
| `lab/start.sh` | Runs when the container starts: starts nginx, then logs you in as `asha` with `su -` |

## Follow along

### 1. Start web-01
From this folder on your laptop:
```bash
docker build -t linux-lab:m02-l02 lab/
docker run -it --rm --name linux-lab --hostname web-01 linux-lab:m02-l02
```
```
asha@web-01:~$
```

### 2. What may Asha do?
```bash
sudo -l
```
Type Asha's lab password (`demo-password-123`). The last line:
```
User asha may run the following commands on web-01:
    (ALL : ALL) ALL
```

### 3. Users and groups
```bash
whoami
id
grep asha /etc/passwd
grep -E '^(root|www-data|ubuntu):' /etc/passwd
cat /etc/shadow
ls -l /etc/passwd /etc/shadow
ps -o user,pid,cmd -C nginx
groups
grep -E '^(adm|sudo|www-data|asha):' /etc/group
```
```
uid=1001(asha) gid=1001(asha) groups=1001(asha),4(adm),27(sudo)
asha:x:1001:1001::/home/asha:/bin/bash
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
cat: /etc/shadow: Permission denied
-rw-r----- 1 root shadow 600 ... /etc/shadow
```
`ps` shows the nginx master as `root` and its workers as `www-data`.

### 4. Add Priya, a team group, and Meera
```bash
sudo useradd -m -s /bin/bash priya
id priya
sudo groupadd devs
sudo usermod -aG devs priya
id priya
sudo adduser --disabled-password --comment "Meera" meera
```
```
uid=1002(priya) gid=1002(priya) groups=1002(priya),1003(devs)
```
Give Priya a (fake) password, so `sudo` can ask for it later. This was done off screen in the video:
```bash
echo 'priya:demo-password-456' | sudo chpasswd
```

### 5. sudo and a narrow sudoers rule for Priya
```bash
sudo grep -E '^(root|%admin|%sudo|@includedir)' /etc/sudoers
sudo visudo -f /etc/sudoers.d/priya
```
`visudo` opens nano. Type these two lines, then **Ctrl+O**, Enter, **Ctrl+X**:
```
# Priya may test and reload nginx, nothing else
priya ALL=(root) NOPASSWD: /usr/sbin/nginx -t, /usr/sbin/nginx -s reload
```
```bash
sudo ls -l /etc/sudoers.d/priya
sudo cat /etc/sudoers.d/priya
```
Try it as Priya:
```bash
sudo -iu priya
sudo -l
sudo nginx -t
sudo cat /etc/shadow
exit
```
For `sudo cat /etc/shadow` type Priya's password (`demo-password-456`):
```
    (root) NOPASSWD: /usr/sbin/nginx -t, /usr/sbin/nginx -s reload
nginx: configuration file /etc/nginx/nginx.conf test is successful
Sorry, user priya is not allowed to execute '/usr/bin/cat /etc/shadow' as root on web-01.
```
Check every sudoers file:
```bash
sudo visudo -c
sudo chmod 0440 /etc/sudoers.d/priya
sudo visudo -c
```
```
/etc/sudoers.d/priya: bad permissions, should be mode 0440
...
/etc/sudoers.d/priya: parsed OK
```

### 6. File permissions: chmod and chown
```bash
cd /srv/allcsvideos
ls -l
./deploy.sh
chmod u+x deploy.sh
ls -l deploy.sh
./deploy.sh
chmod 755 deploy.sh
ls -l deploy.sh
```
```
-bash: ./deploy.sh: Permission denied
-rwxrw-r-- 1 asha asha 44 ... deploy.sh
Deploying allcsvideos...
-rwxr-xr-x 1 asha asha 44 ... deploy.sh
```
The settings file leaks a (fake) database password to every user. Fix it:
```bash
sudo -u priya cat app.env
sudo chown root:www-data app.env
sudo chmod 640 app.env
ls -l app.env
sudo -u www-data cat app.env
sudo -u priya cat app.env
cat app.env
```
```
-rw-r----- 1 root www-data 53 ... app.env
DB_USER=allcs
DB_PASSWORD=demo-password-123   # fake
cat: app.env: Permission denied
cat: app.env: Permission denied
```
Both forms side by side, and symbolic mode:
```bash
stat -c '%A %a %U:%G %n' deploy.sh app.env
chmod g+w,o-rx deploy.sh
ls -l deploy.sh
chmod u=rwx,go=rx deploy.sh
ls -l deploy.sh
```
```
-rwxr-xr-x 755 asha:asha deploy.sh
-rw-r----- 640 root:www-data app.env
-rwxrwx--- 1 asha asha 44 ... deploy.sh
-rwxr-xr-x 1 asha asha 44 ... deploy.sh
```

### 7. Folder permission puzzles
```bash
cd
mkdir puzzle
echo "hello" > puzzle/notes.txt
ls -ld puzzle
```
Puzzle 1, read but no execute:
```bash
chmod 400 puzzle
ls puzzle
cat puzzle/notes.txt
cd puzzle
```
`ls` shows the name `notes.txt`, but `cat` and `cd` are denied.

Puzzle 2, execute but no read:
```bash
chmod 100 puzzle
ls puzzle
cat puzzle/notes.txt
```
`ls: cannot open directory 'puzzle': Permission denied`, but `cat` prints `hello`.

Puzzle 3, read and execute but no write:
```bash
chmod 500 puzzle
rm puzzle/notes.txt
echo "more" >> puzzle/notes.txt
cat puzzle/notes.txt
```
`rm` is denied, but appending works.

Puzzle 4, write on the folder:
```bash
chmod 700 puzzle
sudo touch puzzle/report.txt
ls -l puzzle
rm puzzle/report.txt
ls puzzle
```
`rm` asks `remove write-protected regular empty file 'puzzle/report.txt'?`. Answer `y`, and the root-owned file is gone.

### 8. umask
```bash
umask
touch a.txt
mkdir adir
ls -ld a.txt adir
sudo -i
umask
touch r.txt
mkdir rdir
ls -ld r.txt rdir
exit
umask 027
touch b.txt
mkdir bdir
ls -ld b.txt bdir
grep -E '^(UMASK|USERGROUPS_ENAB)' /etc/login.defs
```
```
0002                                  (asha: files 664, folders 775)
0022                                  (root: files 644, folders 755)
-rw-r----- 1 asha asha    0 ... b.txt
drwxr-x--- 2 asha asha 4096 ... bdir
UMASK           022
USERGROUPS_ENAB yes
```

### 9. Special bits: setuid, sticky, setgid
```bash
ls -l /usr/bin/passwd /etc/shadow
ls -ld /tmp
sudo -u priya touch /tmp/priya-notes.txt
rm -f /tmp/priya-notes.txt
```
```
-rwsr-xr-x 1 root root   72056 ... /usr/bin/passwd
drwxrwxrwt 1 root root 4096 ... /tmp
rm: cannot remove '/tmp/priya-notes.txt': Operation not permitted
```
A shared team folder with setgid:
```bash
sudo mkdir /srv/releases
sudo chown root:devs /srv/releases
sudo chmod 775 /srv/releases
sudo -u priya touch /srv/releases/a.txt
sudo chmod g+s /srv/releases
sudo -u priya touch /srv/releases/b.txt
ls -ld /srv/releases
ls -l /srv/releases
```
```
drwxrwsr-x 2 root devs 4096 ... /srv/releases
-rw-rw-r-- 1 priya priya 0 ... a.txt
-rw-rw-r-- 1 priya devs  0 ... b.txt
```

### 10. The 777 incident, staged on purpose
The upload fails:
```bash
cd /var/www/allcsvideos
ls -ld uploads
sudo -u www-data cp /tmp/lesson-04.mp4 uploads/
```
```
drwxr-xr-x 2 root root 4096 ... uploads
cp: cannot create regular file 'uploads/lesson-04.mp4': Permission denied
```
The forum "fix" (do not do this on a real server):
```bash
sudo chmod -R 777 uploads
sudo -u www-data cp /tmp/lesson-04.mp4 uploads/
ls -l uploads
```
Now any account can vandalise it. `nobody` stands in for any user or any hacked service:
```bash
sudo -u nobody sh -c 'echo hacked > uploads/lesson-01.mp4'
sudo -u nobody rm uploads/lesson-02.mp4
sudo -u nobody touch uploads/shell.php
ls -l uploads
```
```
-rwxrwxrwx 1 root     root           7 ... lesson-01.mp4
-rwxrwxrwx 1 root     root     2097152 ... lesson-03.mp4
-rw-r--r-- 1 www-data www-data 3145728 ... lesson-04.mp4
-rw-r--r-- 1 nobody   nogroup        0 ... shell.php
```

### 11. The real fix
Clean up and restore from last night's backup (use `{1,2}`, see Common mistakes):
```bash
sudo rm uploads/shell.php
sudo cp -p /var/backups/uploads/lesson-0{1,2}.mp4 uploads/
```
Give the folder to the user that writes to it, and set modes with `find` (folders 750, files 640):
```bash
sudo chown -R www-data:www-data uploads
sudo find uploads -type d -exec chmod 750 {} +
sudo find uploads -type f -exec chmod 640 {} +
sudo ls -la uploads
```
```
drwxr-x--- 2 www-data www-data    4096 ... .
-rw-r----- 1 www-data www-data 2097152 ... lesson-01.mp4
```
Prove it:
```bash
sudo -u www-data cp /tmp/lesson-04.mp4 uploads/
sudo -u nobody sh -c 'echo hacked > uploads/lesson-01.mp4'
sudo -u nobody touch uploads/shell.php
ls uploads
```
The copy works, both `nobody` attempts get `Permission denied`, and so does Asha's `ls`. Give only Asha read access with an ACL:
```bash
sudo setfacl -m u:asha:rx uploads
ls -ld uploads
ls uploads
getfacl -p uploads
```
```
drwxr-x---+ 2 www-data www-data 4096 ... uploads
lesson-01.mp4  lesson-02.mp4  lesson-03.mp4  lesson-04.mp4
user::rwx
user:asha:r-x
group::r-x
mask::r-x
other::---
```

### 12. Pitfalls, tried out
sudo and redirection:
```bash
cd
sudo echo "127.0.0.1 allcsvideos.local" >> /etc/hosts
echo "127.0.0.1 allcsvideos.local" | sudo tee -a /etc/hosts
```
The first gives `-bash: /etc/hosts: Permission denied`, the second works.

New groups need a new login:
```bash
sudo usermod -aG devs asha
id
id asha
```
`id` still shows the old groups, `id asha` shows `1003(devs)`.

`usermod -G` without `-a` replaces groups:
```bash
id priya
sudo usermod -G adm priya
id priya
```
`devs` is gone, replaced by `adm`.

A sudoers syntax error, caught by `visudo`:
```bash
printf 'priya ALL=(root) /usr/sbin/nginx -t,\n' > /tmp/bad-rule
cat /tmp/bad-rule
sudo visudo -cf /tmp/bad-rule
```
```
/tmp/bad-rule:1:37: syntax error
priya ALL=(root) /usr/sbin/nginx -t,
                                    ^
```

## Common mistakes
- **`sudo` with redirection.** In `sudo echo ... >> /etc/hosts` your own shell opens the file, not root. Pipe into `sudo tee -a` instead.
  Wildcards have the same trap: your shell expands them before `sudo` runs, so `sudo cp /var/backups/uploads/lesson-0[12].mp4 ...`
  fails with `No such file or directory` because Asha cannot look inside the root-only backup folder. Brace expansion `{1,2}` works.
- **New groups need a new login.** `id` keeps showing the old groups until you log out and back in.
- **`usermod -G` without `-a`** replaces all supplementary groups. Do that to yourself and you can lose `sudo`.
- **Editing sudoers by hand.** One stray comma breaks a rule. Always use `visudo` (and `visudo -c` / `visudo -cf FILE` to check).
- **`chmod -R 777`** gives every account on the server write access. Fix the owner instead, with 750 folders and 640 files.
- **`chmod -R 750`** on a folder of files would make every file executable. Use two `find` commands, one for folders, one for files.

## Clean up
Type `exit` to leave Asha's shell; `--rm` removes the container. Then on your laptop:
```bash
docker rm -f linux-lab        # only if it is still running
docker rmi linux-lab:m02-l02
```

## Next
M02-L03 · Processes, Signals and systemd: [../m02-l03-processes-signals-and-systemd](../m02-l03-processes-signals-and-systemd)
