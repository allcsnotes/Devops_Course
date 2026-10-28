# M03-L01 · Bash Basics

> Video: Module 3, Lesson 1. Watch it first, then follow along here.

## What you'll learn

- What a shell script is, what the shebang (`#!/usr/bin/env bash`) does, and why you run scripts with `./`
- How bash rewrites every line before running it: variables, command substitution, word splitting, globbing
- Variables, `export`, command substitution `$( )` and whole-number arithmetic `$(( ))`
- Quoting: single quotes, double quotes, and why unquoted variables break on spaces and stars
- Decisions with exit codes, `&&`, `||`, `if`, `[[ ]]` tests and `case`
- Loops (`for`, `while`, `while IFS= read -r`), reading input, arguments and arrays, all used to build `morning-check.sh`

## Before you start

- Docker Desktop (or Docker Engine) running, and a terminal. On Windows, use Git Bash or WSL for the commands below.
- The lab server is a container built from the pinned image `ubuntu:24.04` (bash 5.2). One optional step also uses `ubuntu:22.04`.
- Comfortable with the Linux basics from Module 2 (`chmod`, `PATH`, `df`, `awk`, `grep`, exit codes). No earlier lesson folder is needed.

## Files in this folder

| File | What it is |
|------|------------|
| `lab/Dockerfile` | Builds the lab server "web-01": Ubuntu 24.04, nginx, the user `asha`, the sample access log, the practice files |
| `lab/start.sh` | Runs when the container starts: prepares the small `/data` disk, starts nginx |
| `lab/gen_logs.py` | Generates the sample nginx `access.log` from Module 2 (made-up traffic, 73 server errors from the checkout incident) |
| `scripts/hello.sh` | Asha's first script |
| `scripts/conditions.sh` | `if`, `elif`, `else` on a disk percentage |
| `scripts/answer.sh` | `read` an answer, then pick a branch with `case` |
| `scripts/login.sh` | `read -p` and `read -s` (a fake demo password) |
| `scripts/args.sh` | A first look at `$0`, `$1`, `$2`, `$#`, `$@` |
| `scripts/servers.txt` | A small file with a comment, leading spaces and backslashes, for the `read` loops |
| `scripts/report.sh` | A script with Windows (CRLF) line endings, on purpose, for pitfall 5 |
| `scripts/morning-check.v1.sh` | morning-check, version 1: variables only, it just prints |
| `scripts/morning-check.v2.sh` | morning-check, version 2: `if` decisions, OK or WARN |
| `scripts/morning-check.sh` | morning-check, final: mounts array, loop, colours, warning count, summary |
| `.gitattributes` | Keeps LF line endings on checkout, except for `report.sh`, which must stay CRLF |

Inside the container, all of `scripts/` is copied to `~/lesson/`, and the practice files (`hello.sh`, `conditions.sh`,
`answer.sh`, `login.sh`, `args.sh`, `report.sh`, `servers.txt`, and a `reports/` folder) are already in asha's home.

## Follow along

### 1. Start the lab server

Run these from this folder (`scripts/m03-l01-bash-basics`) on your laptop:

```bash
docker build -t bash-lab:m03-l01 -f lab/Dockerfile .
docker run -d --name web01 --hostname web-01 --init --tmpfs /data:size=64m bash-lab:m03-l01
docker exec -it web01 su - asha
```

You are now `asha@web-01:~$`. Every command below runs there, unless a step says "on your laptop".
`/data` is a 64 MB in-memory disk, standing in for the data disk that filled up in Module 2.

### 2. The checklist Asha types by hand

```bash
df -h / /data
pgrep -c -x nginx
awk '$9 >= 500' /var/log/nginx/access.log | wc -l
```

You should see `/data` at about 15%, a count of nginx processes, and `73` server errors.
(The size and usage of `/` depend on your Docker disk, so your numbers there will differ.)

### 3. Watch bash rewrite a line

```bash
cd ~/reports
file="error report.txt"
echo $(whoami) $file *.txt
printf '[%s]\n' $(whoami) $file *.txt
cd
```

`printf '[%s]\n'` prints each argument in brackets, so you can see what the command really received:

```
[asha]
[error]
[report.txt]
[disk.txt]
[error report.txt]
[nginx.txt]
```

`$file` was split into two words (word splitting), and `*.txt` became the file names (globbing).

### 4. A first script

```bash
cat hello.sh
ls -l hello.sh
./hello.sh
```

```
-rw-r--r-- 1 asha asha 91 Oct 20 10:44 hello.sh
-bash: ./hello.sh: Permission denied
```

A new file is never executable. Two ways to run it:

```bash
bash hello.sh
chmod +x hello.sh
ls -l hello.sh
./hello.sh
```

```
Good morning from web-01
asha
```

Why `./`? Without it, bash only looks in the folders on your `PATH`:

```bash
hello.sh
echo $PATH
```

```
-bash: hello.sh: command not found
```

And the two shebang styles:

```bash
which -a bash
ls -ld /bin
bash --version | head -n 1
```

```
/usr/bin/bash
/bin/bash
lrwxrwxrwx 1 root root 7 Apr 22  2024 /bin -> usr/bin
GNU bash, version 5.2.21(1)-release (aarch64-unknown-linux-gnu)
```

(On an Intel/AMD laptop the last part says `x86_64` instead of `aarch64`.)

### 5. Variables

```bash
name=asha
echo $name
echo "Good morning, $name"
```

Braces mark where a variable name ends:

```bash
file=access
echo "$file_2026.log"
echo "${file}_2026.log"
```

```
.log
access_2026.log
```

A variable lives only in this shell until you `export` it:

```bash
greeting=hello
bash -c 'echo "child sees: $greeting"'
export greeting
bash -c 'echo "child sees: $greeting"'
env | grep -E '^(USER|HOME|SHELL|greeting)='
```

```
child sees:
child sees: hello
SHELL=/bin/bash
HOME=/home/asha
USER=asha
greeting=hello
```

Command substitution and arithmetic:

```bash
today=$(date +%F)
echo "Report for $today"
echo "I am $(whoami) on $(hostname)"
echo $(( 7 * 24 ))
used=42
echo "free: $(( 100 - used ))%"
echo $(( 7 / 2 ))
```

`7 / 2` prints `3`: bash only does whole numbers. For decimals, use awk or Python.

### 6. morning-check.sh, version 1

```bash
cat lesson/morning-check.v1.sh
cp lesson/morning-check.v1.sh morning-check.sh
chmod +x morning-check.sh
./morning-check.sh
```

```
Morning check on web-01, Tue 20 Oct
disk /       3% used
5xx errors   73
```

It works, but it does not judge anything yet. (Your date and `/` usage will be your own.)

### 7. Quoting

```bash
echo 'Home: $HOME'
echo "Home: $HOME"
echo 'It costs $5'
echo "It costs $5"
```

```
Home: $HOME
Home: /home/asha
It costs $5
It costs
```

Now a file name with a space in it:

```bash
cd ~/reports
ls -l
file="error report.txt"
wc -l $file
printf '[%s]\n' $file
wc -l "$file"
```

```
wc: error: No such file or directory
wc: report.txt: No such file or directory
0 total
[error]
[report.txt]
5 error report.txt
```

The same bug in a loop, and the fix:

```bash
for f in $(ls); do wc -l $f; done
for f in *; do wc -l "$f"; done
```

And globbing:

```bash
msg="disk at 90% * check it"
echo $msg
echo "$msg"
cd
```

```
disk at 90% disk.txt error report.txt nginx.txt check it
disk at 90% * check it
```

Rule: always put double quotes around variables, unless you have a reason not to.

### 8. Exit codes and decisions

```bash
ls /etc/hostname
echo $?
ls /nope
echo $?
grep -q www-data /etc/passwd
echo $?
grep -q lukas /etc/passwd
echo $?
```

You should see `0`, then `2`, then `0`, then `1`.

```bash
pgrep -x nginx > /dev/null && echo "nginx is up"
pgrep -x apache2 > /dev/null || echo "no apache here"
cat conditions.sh
./conditions.sh
```

```
nginx is up
no apache here
OK: disk at 42%
```

`[` versus `[[`:

```bash
type [
type [[
ls -l /usr/bin/[
```

```
[ is a shell builtin
[[ is a shell keyword
```

Tests inside `[[ ]]`:

```bash
[[ -f /etc/hostname ]] && echo "a file"
[[ -d /var/log/nginx ]] && echo "a folder"
name=""
[[ -z $name ]] && echo "empty"
[[ -n $HOME ]] && echo "not empty"
[[ 5 -lt 10 ]] && echo "5 is less than 10"
[[ $USER == asha ]] && echo "hi, asha"
[[ $HOSTNAME =~ ^web-[0-9]+$ ]] && echo "a web server"
```

`case`, with three runs. Type `y`, then `no`, then `maybe` at the prompt:

```bash
cat answer.sh
./answer.sh
./answer.sh
./answer.sh
```

```
Clear the old upload cache? [y/n] y
Clearing the cache
Clear the old upload cache? [y/n] no
Leaving it alone
Clear the old upload cache? [y/n] maybe
Please answer y or n
```

### 9. morning-check.sh, version 2

```bash
cat lesson/morning-check.v2.sh
cp lesson/morning-check.v2.sh morning-check.sh
./morning-check.sh
```

```
Morning check on web-01, Tue 20 Oct
OK    disk / is 3% full
OK    nginx is running
WARN  73 5xx errors in /var/log/nginx/access.log
```

### 10. Loops

```bash
for host in web-01 db-01 bastion; do echo "checking $host"; done
for f in /var/log/nginx/*.log; do echo "$f: $(wc -l < "$f") lines"; done
for i in {1..5}; do echo -n "$i "; done; echo
for (( i = 1; i <= 3; i++ )); do echo "try $i"; done
n=1
while (( n <= 3 )); do echo "attempt $n"; n=$(( n + 1 )); done
```

```
/var/log/nginx/access.log: 5928 lines
/var/log/nginx/error.log: 0 lines
```

Reading a file line by line. Look at `servers.txt` first, then compare three ways to read it:

```bash
cat servers.txt
for line in $(cat servers.txt); do echo "[$line]"; done | head -n 6
while read line; do echo "[$line]"; done < servers.txt
while IFS= read -r line; do echo "[$line]"; done < servers.txt
```

The first splits into words, the second loses the leading spaces and the backslashes, the third keeps every line exactly:

```
[  bastion   the only door in]
[nas-01   backups on \\nas-01\daily]
```

`continue` and `break`:

```bash
while IFS= read -r line; do [[ $line == "#"* ]] && continue; echo "$line"; done < servers.txt
for i in {1..10}; do (( i == 3 )) && continue; (( i == 6 )) && break; echo -n "$i "; done; echo
```

The last one prints `1 2 4 5`.

### 11. Input, arguments and arrays

Type `Asha`, then any password (nothing shows while you type it):

```bash
cat login.sh
./login.sh
```

```
Your name: Asha
Demo password (fake):
Hello, Asha. Your password has 17 characters.
```

(The length is whatever you typed. The video used a 17-character demo password.)

```bash
./args.sh web-01 db-01
```

```
script: ./args.sh
first:  web-01
second: db-01
count:  2
all:    web-01 db-01
```

```bash
servers=(web-01 db-01 bastion)
echo "${servers[0]}"
echo "${#servers[@]}"
for s in "${servers[@]}"; do echo "next: $s"; done
```

### 12. The final morning-check.sh

```bash
cat lesson/morning-check.sh
cp lesson/morning-check.sh morning-check.sh
./morning-check.sh
```

```
Morning check on web-01, Tue 20 Oct
OK    disk / is 3% full
OK    disk /data is 15% full
OK    nginx is running
WARN  73 5xx errors in /var/log/nginx/access.log
WARN  1 check(s) need a look
```

OK prints in green, WARN in yellow. Now break web-01 on purpose: fill the data disk and stop nginx.

```bash
fallocate -l 47M /data/staged-fill.bin
sudo nginx -s stop
df -h /data
./morning-check.sh
echo $?
```

```
tmpfs            64M   56M  8.0M  88% /data
...
WARN  disk /data is 88% full
WARN  nginx is not running
WARN  73 5xx errors in /var/log/nginx/access.log
WARN  3 check(s) need a look
0
```

The script found 3 problems and still exits with `0`. Fixing that is the first job of the next lesson.
Put things back:

```bash
sudo nginx
rm /data/staged-fill.bin
./morning-check.sh
```

Both disks and nginx are OK again; only the log warning is left.

### 13. Pitfalls, live

```bash
limit = 80
limit= 80
limit=80
echo $limit
```

```
-bash: limit: command not found
-bash: 80: command not found
80
```

```bash
used=42
[$used -gt 80] && echo full
[ $used -gt 80 ] || echo "not full"
name=""
[ $name == asha ] && echo hi
[ "$name" == asha ] || echo "not asha"
[[ $name == asha ]] || echo "not asha"
```

```
-bash: [42: command not found
not full
-bash: [: ==: unary operator expected
not asha
not asha
```

```bash
[[ 10 > 9 ]]; echo $?
[[ 10 -gt 9 ]]; echo $?
[[ 7 == 07 ]]; echo $?
[[ 7 -eq 07 ]]; echo $?
```

You should see `1`, `0`, `1`, `0`.

Windows line endings:

```bash
./report.sh
cat -A report.sh
bash report.sh
```

```
-bash: ./report.sh: cannot execute: required file not found
#!/bin/bash^M$
...
report.sh: line 3: cd: $'/var/log/nginx\r': No such file or directory
Report for web-01
```

Fix it:

```bash
sed -i 's/\r$//' report.sh
cat -A report.sh
./report.sh
```

```
#!/bin/bash$
...
Report for web-01
```

Optional, on your laptop: older bash (5.1 on Ubuntu 22.04) prints the message most guides show.

```bash
docker run -d --name legacy01 --hostname legacy-01 --init ubuntu:22.04 sleep infinity
docker cp scripts/report.sh legacy01:/root/report.sh
docker exec legacy01 bash -c 'chmod +x /root/report.sh; bash --version | head -n 1; cd /root && ./report.sh'
docker rm -f legacy01
```

You should see bash 5.1.16, then an error that ends in:

```
./report.sh: /bin/bash^M: bad interpreter: No such file or directory
```

## Common mistakes

1. **Spaces around `=`.** `limit = 80` runs a command called `limit`; `limit= 80` runs a command called `80`. Assignments have no spaces.
2. **`[` without spaces.** `[` is a command, so `[$used -gt 80]` looks for a command called `[42`. Write `[ $used -gt 80 ]`, or better, `[[ ... ]]`.
3. **Unquoted variables in single brackets.** An empty `$name` disappears, and `[ == asha ]` fails with "unary operator expected". Quote it, or use `[[ ]]`.
4. **Comparing numbers as text.** Inside `[[ ]]`, `>` and `==` compare text: `10 > 9` is false and `7 == 07` is false. Use `-gt`, `-eq`, `-lt` and friends for numbers.
5. **Windows line endings.** A script saved with CRLF fails with "cannot execute: required file not found" (or "bad interpreter: /bin/bash^M" on older bash). Find it with `cat -A`, fix it with `sed -i 's/\r$//'`, and set your editor to LF.

Also from the lesson: `for f in $(ls)` and `for line in $(cat file)` split on spaces; use `for f in *` and `while IFS= read -r line`.

## Clean up

On your laptop:

```bash
docker rm -f web01
docker image rm bash-lab:m03-l01
```

The next lesson builds its own copy of web-01, so you can remove this one.

## Next

M03-L02 · Robust Scripts: [../m03-l02-robust-scripts](../m03-l02-robust-scripts)
