# M03-L02 · Robust Scripts

> Video: Module 3, Lesson 2. Watch it first, then follow along here.

## What you'll learn

- Why a script that carries on after a failure, and then exits with 0, is dangerous
- Functions: arguments, `local` variables, printing an answer versus returning an exit code
- Script arguments (`"$@"`, `"$*"`, `shift`), a usage message, and options with `getopts`
- Exit codes that mean something (0, 1, 2, 126, 127, 130), `return` versus `exit`, and `command -v`
- `set -euo pipefail`, where `set -e` has gaps, `trap cleanup EXIT` with `mktemp`, logging to stderr, dry runs
- Linting with shellcheck, and rebuilding `morning-check.sh` into a tool cron and monitoring can trust

## Before you start

- Docker Desktop (or Docker Engine) running, and a terminal. On Windows, use Git Bash or WSL for the commands below.
- The lab server is a container built from the pinned image `ubuntu:24.04` (bash 5.2). shellcheck runs from the pinned
  image `koalaman/shellcheck:v0.11.0`.
- You should have done [M03-L01 · Bash Basics](../m03-l01-bash-basics). This folder builds its own lab server, so you
  do not need the one from that lesson.

## Files in this folder

| File | What it is |
|------|------------|
| `lab/Dockerfile` | Builds the lab server "web-01": Ubuntu 24.04, nginx, the user `asha`, the sample access log, this lesson's scripts, a sandbox folder |
| `lab/start.sh` | Runs when the container starts: prepares the small `/data` disk, starts nginx |
| `lab/gen_logs.py` | Generates the sample nginx `access.log` from Module 2 (made-up traffic, 73 server errors) |
| `scripts/cleanup.v1.sh` | The cleanup script from the opening story: `cd` fails, `rm` runs anyway, it reports success |
| `scripts/cleanup.v2.sh` | The same script with `set -euo pipefail` |
| `scripts/cleanup.v3.sh` | Final cleanup: a `-n` dry run, `rm -f -- ./*.tar.gz`, safe to re-run |
| `scripts/funcs.sh` | Functions: arguments, a printed answer, an exit-code answer |
| `scripts/params.sh` | What a script receives: `$0`, `$#`, `"$@"`, `"$*"`, unquoted `$@` |
| `scripts/collect.sh` | `shift` in a loop, plus a `usage` function that exits with 2 |
| `scripts/opts.sh` | Options with `getopts` |
| `scripts/exitreturn.sh` | `return` leaves a function, `exit` (in a `die` function) ends the script |
| `scripts/typo.sh`, `scripts/typo.v2.sh` | A misspelled variable, without and with `set -u` |
| `scripts/gap.sh` | Where `set -e` does NOT stop the script |
| `scripts/traps.sh` | `mktemp` plus `trap cleanup EXIT` and an `ERR` trap |
| `scripts/archive-logs.sh` | A quick script full of shellcheck findings |
| `scripts/archive-logs.v2.sh` | The same script with every finding fixed |
| `scripts/morning-check.v1.sh` | morning-check as it ended in M03-L01 (exits 0 even with problems) |
| `scripts/morning-check.sh` | morning-check v2: strict mode, help, options, logging, check functions, honest exit codes |
| `scripts/counter.sh`, `masked.sh`, `noisy.sh`, `int.sh` | The pitfall demos |
| `.gitattributes` | Keeps LF line endings on checkout, also on Windows |

Inside the container, all of `scripts/` is copied to `~/lesson/`. The practice scripts are already in asha's home, and
`~/cleanup.sh` starts as version 1. When a step swaps in a new version, it copies it from `~/lesson/`.

## Follow along

### 1. Start the lab server

Run these from this folder (`scripts/m03-l02-robust-scripts`) on your laptop:

```bash
docker build -t bash-lab:m03-l02 -f lab/Dockerfile .
docker run -d --name web01 --hostname web-01 --init --tmpfs /data:size=64m bash-lab:m03-l02
docker exec -it web01 su - asha
```

If `web01` from M03-L01 still exists, remove it first with `docker rm -f web01`.
You are now `asha@web-01:~$`. Every command below runs there, unless a step says "on your laptop".

### 2. The cleanup that "succeeded"

`~/sandbox/app` is a staged sandbox with three empty placeholder files. Never try this in a real app folder.

```bash
cat ~/cleanup.sh
cd ~/sandbox/app
ls
~/cleanup.sh
echo $?
ls
cd
```

```
app.env  index.html  server.jar
/home/asha/cleanup.sh: line 4: cd: /home/asha/sandbox/releases/old: No such file or directory
cleanup done
0
```

The last `ls` prints nothing: `cd` failed, bash carried on, and `rm -f *` ran in the folder you were standing in.

### 3. Functions

```bash
cat funcs.sh
./funcs.sh
```

```
Hello Asha, from web-01
/data is 15% used
nginx: running
apache2: not running
```

Variables are global unless you mark them `local`:

```bash
count=5
leak() { count=99; }
leak; echo $count
count=5
safe() { local count=99; }
safe; echo $count
```

You should see `99`, then `5`. And an answer as an exit code:

```bash
is_up() { pgrep -x "$1" > /dev/null; }
is_up nginx; echo $?
is_up apache2; echo $?
```

You should see `0`, then `1`.

### 4. Arguments

```bash
./params.sh web-01 "error report.txt" db-01
```

```
script: ./params.sh
count:  3
first:  web-01
second: error report.txt
quoted "$@":
  [web-01]
  [error report.txt]
  [db-01]
quoted "$*":
  [web-01 error report.txt db-01]
unquoted $@:
  [web-01]
  [error]
  [report.txt]
  [db-01]
```

`shift` and a usage message:

```bash
./collect.sh web-01 a.log b.log c.log
./collect.sh web-01
echo $?
```

```
target: web-01
file: a.log (3 left)
file: b.log (2 left)
file: c.log (1 left)
usage: collect.sh TARGET FILE...
2
```

### 5. Options with getopts

```bash
cat opts.sh
./opts.sh -v -t 90 / /data
./opts.sh -vt 90
./opts.sh /data
```

```
verbose=1 limit=90
mounts: / /data
verbose=1 limit=90
mounts:
verbose=0 limit=80
mounts: /data
```

Mistakes:

```bash
./opts.sh -x
echo $?
./opts.sh -t
echo $?
./opts.sh -h
```

```
opts.sh: unknown option -x
2
opts.sh: -t needs a value
2
usage: opts.sh [-h] [-v] [-t PERCENT] [MOUNT...]
```

### 6. Exit codes

```bash
chmod -x funcs.sh
./funcs.sh; echo $?
chmod +x funcs.sh
nosuchcmd; echo $?
```

```
-bash: ./funcs.sh: Permission denied
126
-bash: nosuchcmd: command not found
127
```

Run `sleep 30`, press Ctrl+C, then check the code:

```bash
sleep 30
echo $?
```

You should see `130` (128 + signal 2, SIGINT).

`return` versus `exit`, and checking that a tool exists:

```bash
./exitreturn.sh
echo $?
command -v awk
command -v curl || echo "curl is not installed"
```

```
found /data
no such folder: /backup
check failed, carrying on
fatal: giving up
1
/usr/bin/awk
curl is not installed
```

### 7. Strict mode: set -euo pipefail

`-e`: swap in version 2 of the cleanup script, put the placeholder files back, and stage the same accident:

```bash
cp lesson/cleanup.v2.sh cleanup.sh
cd ~/sandbox/app
touch app.env index.html server.jar
~/cleanup.sh
echo $?
ls
cd
```

```
/home/asha/cleanup.sh: line 5: cd: /home/asha/sandbox/releases/old: No such file or directory
1
app.env  index.html  server.jar
```

`-u`: a misspelled variable (`tmp_dri` instead of `tmp_dir`):

```bash
cat typo.sh
./typo.sh
```

Without `-u`, the empty variable turns the path into `/`, and `ls` lists the root of the whole server. Now with `set -u`:

```bash
cp lesson/typo.v2.sh typo.sh
./typo.sh
echo $?
```

```
./typo.sh: line 6: tmp_dri: unbound variable
1
```

`-o pipefail`: count errors in a misspelled log file:

```bash
awk '$9 >= 500' /var/log/nginx/acess.log | wc -l
echo $?
set -o pipefail
awk '$9 >= 500' /var/log/nginx/acess.log | wc -l
echo $?
set +o pipefail
```

```
awk: cannot open "/var/log/nginx/acess.log" (No such file or directory)
0
0
...
2
```

The same `0` on screen both times, but with pipefail the exit code is `2`.

A gap in `set -e`:

```bash
cat gap.sh
./gap.sh
echo $?
```

```
cp: cannot create regular file '/backup/': Not a directory
backup finished
backup OK
cp: cannot create regular file '/backup/': Not a directory
1
```

Called as an `if` condition, the failing function carries on. Called on its own, it stops the script.

### 8. Traps and temp files

```bash
cat traps.sh
./traps.sh /data
ls /tmp/tmp.*
```

```
working in /tmp/tmp.inwNF4fWKV
/data 15%
cleanup: removed /tmp/tmp.inwNF4fWKV
ls: cannot access '/tmp/tmp.*': No such file or directory
```

(The random part of the file name will differ.) A mount that does not exist:

```bash
./traps.sh /nope
echo $?
```

```
df: /nope: No such file or directory
error on line 14
cleanup: removed /tmp/tmp.8GxkSba7eq
1
```

And an interrupt: run this, press Ctrl+C while it sleeps, then check:

```bash
./traps.sh / 30
echo $?
ls /tmp/tmp.*
```

```
^Ccleanup: removed /tmp/tmp.3cFPvcgUqJ
130
ls: cannot access '/tmp/tmp.*': No such file or directory
```

### 9. Logging, dry runs, idempotency

```bash
log() { printf "%s %s\n" "$(date "+%F %T")" "$*" >&2; }
log "backup started"
log "backup started" 2> /dev/null
```

The first prints the date, the time and the message; the second prints nothing, because the message went to stderr.

Swap in cleanup version 3, which takes `-n` for a dry run, and create the old releases folder:

```bash
cp lesson/cleanup.v3.sh cleanup.sh
mkdir -p ~/sandbox/releases/old
cd ~/sandbox/releases/old
touch v2.12.0.tar.gz v2.13.0.tar.gz
ls
~/cleanup.sh -n
ls
~/cleanup.sh
ls
~/cleanup.sh; echo $?
cd
```

```
dry run: rm -f -- ./v2.12.0.tar.gz ./v2.13.0.tar.gz
cleanup done
v2.12.0.tar.gz  v2.13.0.tar.gz
cleanup done
cleanup done
0
```

Running it twice gives the same result as running it once: that is idempotency.

### 10. shellcheck

On your laptop (a second terminal), from this lesson folder:

```bash
cd scripts
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:v0.11.0 cleanup.v1.sh
```

```
In cleanup.v1.sh line 4:
cd "$HOME/sandbox/releases/old"
^-----------------------------^ SC2164 (warning): Use 'cd ... || exit' or 'cd ... || return' in case cd fails.
...
In cleanup.v1.sh line 5:
rm -f *
      ^-- SC2035 (info): Use ./*glob* or -- *glob* so names with dashes won't become options.
```

(In the video the file was called `cleanup.sh`; here it is `cleanup.v1.sh`, so the file name in the output differs.)

```bash
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:v0.11.0 archive-logs.sh
```

You should see SC2086 (three times), SC2164, SC2045 (an error: iterating over `ls` output), SC2155 and SC2012,
and exit code 1. The fixed version is clean:

```bash
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:v0.11.0 archive-logs.v2.sh
echo $?
```

No output, exit code `0`. Each code has a wiki page, for example https://www.shellcheck.net/wiki/SC2164.
On Windows PowerShell, use `${PWD}` instead of `$PWD`.

### 11. morning-check.sh v2

Back in the container. Read the final script, then install it:

```bash
cat lesson/morning-check.sh
cp lesson/morning-check.sh morning-check.sh
./morning-check.sh -h
echo $?
```

```
usage: morning-check.sh [-h] [-v] [-t PERCENT] [-l LOGFILE] [MOUNT...]
  -h          show this help
  -v          verbose: log each step to stderr
  -t PERCENT  warn when a disk is this full (default 80)
  -l LOGFILE  access log to scan (default /var/log/nginx/access.log)
  MOUNT...    disks to check (default / and /data)
exit codes: 0 all OK, 1 something needs a look, 2 usage error
0
```

Wrong usage:

```bash
./morning-check.sh -x
echo $?
./morning-check.sh -t
./morning-check.sh -t 200
echo $?
```

```
2026-10-20 11:06:24 error: unknown option -x (try -h)
2
2026-10-20 11:06:26 error: -t needs a value (try -h)
2026-10-20 11:06:27 error: -t needs a number from 1 to 100, got '200'
2
```

A normal run, then verbose with a 10% limit on `/data` only:

```bash
./morning-check.sh
echo $?
./morning-check.sh -v -t 10 /data
echo $?
```

```
Morning check on web-01, Tue 20 Oct
OK    disk / is 3% full
OK    disk /data is 15% full
OK    nginx is running
WARN  73 5xx errors in /var/log/nginx/access.log
2026-10-20 11:07:41 finished: 1 check(s) need a look
1
```

The two streams:

```bash
./morning-check.sh 2> /dev/null
./morning-check.sh > report.txt
cat report.txt
```

With stderr thrown away, only the report is left. With stdout in `report.txt`, only the log line reaches the screen,
and the file holds a clean report with no colour codes.

Exit code 0, using only the first 1000 lines of the log (from before the incident):

```bash
head -n 1000 /var/log/nginx/access.log > quiet.log
./morning-check.sh -l quiet.log
echo $?
```

```
OK    no 5xx errors
2026-10-20 11:06:40 finished: all checks passed
0
```

The misspelled log is no longer a silent zero:

```bash
./morning-check.sh -l /var/log/nginx/acess.log
echo $?
```

```
awk: cannot open "/var/log/nginx/acess.log" (No such file or directory)
WARN  cannot read /var/log/nginx/acess.log
2026-10-20 11:06:43 finished: 1 check(s) need a look
1
```

Break web-01 on purpose, and call the script the way cron or another script would:

```bash
fallocate -l 47M /data/staged-fill.bin
sudo nginx -s stop
./morning-check.sh || echo "exit code $?: needs a look"
```

```
WARN  disk /data is 88% full
WARN  nginx is not running
WARN  73 5xx errors in /var/log/nginx/access.log
2026-10-20 11:06:48 finished: 3 check(s) need a look
exit code 1: needs a look
```

Put things back:

```bash
sudo nginx
rm /data/staged-fill.bin
./morning-check.sh; echo $?
```

Back to one warning, exit code `1`. And on your laptop (still in `scripts/`), shellcheck on the final script prints nothing:

```bash
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:v0.11.0 morning-check.sh
echo $?
```

### 12. Pitfalls, live

```bash
cat counter.sh
./counter.sh
echo $?
```

```
checking /: 3%
checking /data: 15%
1
```

No summary: `(( full++ ))` returned the old value, 0, which counts as a failure under `set -e`.

```bash
./masked.sh
echo $?
```

```
grep: /etc/morning-check.conf: No such file or directory
masked: value is ''
grep: /etc/morning-check.conf: No such file or directory
2
```

```bash
./noisy.sh
```

```
used is: checking /data
15
./noisy.sh: line 9: ((: checking /data
15: division by 0 (error token is "data
15")
```

```bash
f() { return 300; }; f; echo $?
bash -c 'exit 256'; echo $?
```

You should see `44`, then `0`. Finally, run `./int.sh`, press Ctrl+C during the wait, then `echo $?`:

```bash
./int.sh
echo $?
```

```
step 1: waiting
^Ccleaning up
step 2: deleting old releases
0
```

## Common mistakes

1. **`(( count++ ))` under `set -e`.** It returns the old value; when that is 0, `set -e` ends the script. Write `count=$(( count + 1 ))`.
2. **`local value=$(command)` hides failures.** `local` itself succeeds, so the failure is lost (shellcheck SC2155). Declare `local value` on one line, assign on the next.
3. **Messages on stdout inside a function whose output you capture.** The message ends up in the variable. Send messages to stderr (`>&2`).
4. **Exit codes above 255.** An exit code is one byte: `return 300` becomes 44, `exit 256` becomes 0 (success). Keep your own codes small.
5. **Trapping INT without exiting.** The script runs cleanup, then carries on with the next step. Use `trap cleanup EXIT`, or end an INT trap with `exit 130`.

Also from the lesson: `set -e` is switched off inside `if` conditions and before `&&` or `||`, so check the commands that
matter yourself; always pass arguments on with `"$@"` in quotes; use `${1:-}` for a variable that may really be unset.

## Clean up

On your laptop:

```bash
docker rm -f web01
docker image rm bash-lab:m03-l02 koalaman/shellcheck:v0.11.0
```

Keep the shellcheck image if you want to lint your own scripts later.

## Next

M03-L03 · Scheduling and Automation: [../m03-l03-scheduling-and-automation](../m03-l03-scheduling-and-automation)
