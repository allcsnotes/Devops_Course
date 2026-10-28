# M02-L04 · Text Processing
> Video: Module 2, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- The three streams every process has (standard input 0, standard output 1, standard error 2) and how redirection (`>`, `>>`, `2>`, `2>&1`, `&>`, `<`) and pipes (`|`) rewire them
- `grep` to keep the lines you want, with `-c`, `-i`, `-v`, `-n`, `-A/-B/-C`, `-r`, `-E` and `-o`
- `cut`, `sort` and `uniq -c` to pick columns and count, including the classic "top N" pipeline
- `awk` for fields, conditions, counters, sums and arrays; `sed` for substitutions, line ranges and safe in-place edits
- `tr`, `xargs` and `tee` as small helpers
- How to answer an incident's questions (when, where, who, why) one pipeline at a time, instead of scrolling a log

## Before you start
- Docker Desktop (or Docker Engine) running on your laptop. Everything runs inside a small Ubuntu 24.04 container, so it works the same on macOS, Windows and Linux.
- You only need this folder. The story continues from M02-L02 (asha is in the `adm` group) and M02-L03 (the API), but no files from those lessons are needed.
- The logs are a **generated sample** made for this lesson (`lab/gen_logs.py`), with a real-looking incident staged inside. All IP addresses are documentation ranges and all emails are `@example.com`.

## Files in this folder
| File | What it is |
|---|---|
| `lab/Dockerfile` | Builds the "web-01" server from `ubuntu:24.04` |
| `lab/setup.sh` | Runs during the build: creates user `asha`, the logs in `/var/log/nginx` and `/var/log/allcsvideos`, and the app settings in `/srv/allcsvideos` |
| `lab/gen_logs.py` | Generates `access.log` (nginx combined format, 5928 lines) and `api.log` (1500 lines). Fixed random seed, so you get the same numbers as the video |
| `lab/up.sh` | Builds the image and starts the `web-01` container |
| `lab/down.sh` | Removes the container and the image |

## Follow along

### 1. Start the server and log in as asha
```bash
./lab/up.sh
docker exec -it web-01 su - asha
```
You should land in asha's home folder:
```
asha@web-01:~$
```

### 2. Redirection
One name that exists and one that does not. Both lines land on the screen:
```bash
ls /etc/hostname /nope
```
```
ls: cannot access '/nope': No such file or directory
/etc/hostname
```
Send standard output to a file. The error still shows; the name went into the file:
```bash
ls /etc/hostname /nope > out.txt
cat out.txt
```
`>>` appends, a single `>` replaces the whole file:
```bash
echo "second line" >> out.txt
cat out.txt
echo "fresh start" > out.txt
cat out.txt
```
```
/etc/hostname
second line
...
fresh start
```
`2>` redirects standard error only:
```bash
ls /etc/hostname /nope 2> err.txt
cat err.txt
```
Both streams into one file, the long way and the Bash shortcut:
```bash
ls /etc/hostname /nope > all.txt 2>&1
cat all.txt
ls /etc/hostname /nope &> all.txt
cat all.txt
```
Order matters. Here `2>&1` copies stream 1 while it still points at the screen, so the error still shows:
```bash
ls /etc/hostname /nope 2>&1 > out.txt
cat out.txt
```
Throw errors away with `/dev/null`:
```bash
ls /etc/hostname /nope 2> /dev/null
```
Feed a file into standard input with `<`. Now `wc` never sees a file name, so it prints just the number:
```bash
wc -l /var/log/nginx/access.log
wc -l < /var/log/nginx/access.log
```
```
5928 /var/log/nginx/access.log
5928
```

### 3. A first look at the logs
```bash
cd /var/log/nginx
ls -lh
wc -l access.log ../allcsvideos/api.log
head -n 1 access.log
tail -n 3 ../allcsvideos/api.log
head -n 3000 access.log | tail -n 1
```
```
-rw-r----- 1 www-data adm 1.2M Oct 19 21:51 access.log
-rw-r----- 1 www-data adm    0 Oct 19 20:00 error.log
...
   5928 access.log
   1500 ../allcsvideos/api.log
```
In the nginx combined format, field 1 is the client IP, field 4 the time, fields 6 and 7 the method and path, field 9 the status code and field 10 the reply size in bytes. Then come the referrer and the user agent, in quotes.

### 4. grep
```bash
grep 'POST /api/checkout' access.log | head -n 2
grep -c 'POST /api/checkout' access.log           # 222
grep -c error ../allcsvideos/api.log              # 0: grep is case sensitive
grep -ci error ../allcsvideos/api.log             # 146
grep -c WARN ../allcsvideos/api.log               # 955
grep WARN ../allcsvideos/api.log | grep -v 'login failed'
grep -n SMTP ../allcsvideos/api.log
grep -m 1 -A 4 ERROR ../allcsvideos/api.log
grep -rn LOG_LEVEL /srv/allcsvideos
grep -cE '\.php |/\.env ' access.log              # 14 bot probes
grep -oE '/[a-z-]+\.php|/\.env' access.log | head -n 4
```
The first ERROR plus four lines after it is a Python traceback:
```
2026-10-19 20:31:17,412 ERROR progress: database query failed for /api/progress
Traceback (most recent call last):
  File "/opt/allcsvideos/api.py", line 88, in progress
    rows = db.fetch_progress(user_id)
ConnectionResetError: [Errno 104] Connection reset by peer
```

### 5. cut, sort, uniq
```bash
cut -d' ' -f1 access.log | head -n 3
cut -d' ' -f9 access.log | uniq -c | head -n 4     # not a real count: uniq only merges neighbours
cut -d' ' -f9 access.log | sort | uniq -c
cut -d' ' -f9 access.log | sort | uniq -c | sort -rn
cut -d' ' -f1 access.log | sort | uniq -c | sort -rn | head -n 5
```
```
    935 192.0.2.66
    199 198.51.100.34
    121 198.51.100.163
    112 198.51.100.36
     98 198.51.100.88
```
Sorting by a column, with numbers versus human-readable sizes:
```bash
ls -lh /var/log/*/*.log | sort -k5 -n      # wrong: 1.2M before 7.3K
ls -lh /var/log/*/*.log | sort -k5 -h      # right: K before M
```
(Your apt log sizes and dates will differ from the video; the order rule is what matters.)

### 6. awk
```bash
awk '{print $1, $9}' access.log | head -n 3
awk '$9 == 404 {print $1, $7}' access.log | head -n 3
awk '$9 >= 500 {n++} END {print n}' access.log
awk '{b += $10} END {print b}' access.log
awk '{b += $10} END {printf "%.1f MB\n", b/1024/1024}' access.log
awk '{n[$9]++} END {for (s in n) print s, n[s]}' access.log
awk '{n[$9]++} END {for (s in n) printf "%-5s %6d\n", s, n[s]}' access.log | sort
```
```
73
106697979
101.8 MB
...
200     4447
302      132
304      308
401      954
404       14
500       73
```

### 7. sed
```bash
echo 2026-10-19 | sed 's/-/./'
echo 2026-10-19 | sed 's/-/./g'
head -n 2 access.log | sed -E 's/^([0-9.]+)\.[0-9]+ /\1.x /' | cut -c1-70
cd /srv/allcsvideos
sed -n '4,6p' app.env
sed '/^#/d; /^$/d' app.env
sed 's/^LOG_LEVEL=info$/LOG_LEVEL=debug/' app.env | grep LOG
grep LOG app.env                            # still info: sed only wrote to standard output
```

### 8. tr and xargs
```bash
echo 'GET /API/Checkout' | tr 'A-Z' 'a-z'
ls -l /var/log/nginx/*.log | tr -s ' ' | cut -d' ' -f5,9
find /var/log -name '*.log' -size +100k 2>/dev/null | xargs ls -lh
```

### 9. The incident: why does checkout fail?
How many server errors? `tee` keeps a copy as evidence and still passes the lines on:
```bash
cd /var/log/nginx
awk '$9 == 500' access.log | tee ~/500s.log | wc -l
```
When did they start?
```bash
awk '$9 == 500 {print $4}' access.log | head -n 3
awk '$9 == 500 {print $4}' access.log | cut -c14-18 | uniq -c
```
```
      1 20:31
      9 21:40
     12 21:41
...
```
Which endpoint?
```bash
awk '$9 == 500 {print $7}' access.log | sort | uniq -c | sort -rn
```
```
     72 /api/checkout
      1 /api/progress
```
Who is affected?
```bash
awk '$9 == 500 {print $1}' access.log | sort -u | wc -l                        # 37 clients
awk '$9 == 500 {print $1}' access.log | sort | uniq -c | sort -rn | head -n 3   # nobody has more than 3
```
Is the busiest address, 192.0.2.66, the cause?
```bash
awk '$1 == "192.0.2.66" {print $6, $7, $9}' access.log | sort | uniq -c
awk '$1 == "192.0.2.66" && $9 == 500' access.log | wc -l
```
```
    935 "POST /login 401
0
```
Someone is guessing passwords (a separate problem, for the firewall lesson in Module 4), but it causes none of the 500s.

Is the server overloaded? Requests per minute:
```bash
awk '{print substr($4, 14, 5)}' access.log | uniq -c | tail -n 14
```
Between 49 and 87 a minute, before 21:40 and after. Traffic is normal. Now the API's own log:
```bash
cd ../allcsvideos
grep -c ERROR api.log
grep -o 'TimeoutError.*' api.log | sort | uniq -c
sed -n '/release v2.14.0/,/ERROR/p' api.log | grep -v 'login failed'
grep -rn PAYMENT_TIMEOUT /srv/allcsvideos
```
```
     72 TimeoutError: payment gateway did not answer within 300 ms
...
/srv/allcsvideos/app.env:8:PAYMENT_TIMEOUT_MS=300
/srv/allcsvideos/releases/v2.13.4/app.env:8:PAYMENT_TIMEOUT_MS=3000
```
One missing zero. The fix, in place, with a backup:
```bash
cd /srv/allcsvideos
sed -i.bak 's/^PAYMENT_TIMEOUT_MS=300$/PAYMENT_TIMEOUT_MS=3000/' app.env
diff app.env.bak app.env
ls app.env*
```
```
8c8
< PAYMENT_TIMEOUT_MS=300
---
> PAYMENT_TIMEOUT_MS=3000
```

### 10. See the pitfalls for yourself
```bash
cd /var/log/nginx
grep POST /api/checkout access.log | head -n 2       # no quotes: /api/checkout is read as a file name
awk "{print $1}" access.log | head -n 1               # double quotes: the shell eats $1, awk prints whole lines
head -n 1 access.log | grep -o '".*"'                 # greedy
head -n 1 access.log | grep -o '"[^"]*"'              # stops at the next quote
head -n 1 access.log | cut -d' ' -f12                 # only the first word of the user agent
head -n 1 access.log | awk -F'"' '{print $6}'         # the whole user agent
cd /srv/allcsvideos
sed -i '' 's/^WORKERS=2$/WORKERS=4/' app.env          # macOS syntax, fails on GNU sed
grep WORKERS app.env                                  # unchanged
cd /var/log/nginx
cat access.log | grep -c checkout
grep -c checkout access.log
```

Type `exit` to leave asha's shell.

## Common mistakes
- **Forgetting quotes.** `grep POST /api/checkout access.log` is three words: the pattern `POST` and two files. Quote patterns with spaces, and give `awk` single quotes so the shell does not replace `$1` before awk runs.
- **`>` instead of `>>`.** A single `>` replaces the whole file.
- **Redirection order.** `2>&1 > file` still prints errors; write `> file 2>&1`.
- **Greedy patterns.** `".*"` matches from the first quote to the last one on the line; use `"[^"]*"`.
- **Fields with spaces inside.** `cut -d' '` cannot read the user agent; split on the quote with `awk -F'"'`.
- **`sed -i ''` on a Mac.** macOS sed wants a suffix after `-i`; GNU sed (Ubuntu) only reads a suffix attached to the `i`. Write `sed -i.bak ...` with no space: it works on both.
- **`uniq` without `sort`.** It only merges lines that sit next to each other. Sort first.
- **Useless use of cat.** `grep`, `awk` and `sed` open files themselves; in scripts, pass the file name.

## Clean up
```bash
./lab/down.sh
```
This removes the `web-01` container and the `text-lab:1` image. Everything you created (out.txt, 500s.log, app.env.bak) lived inside the container.

## Next
M02-L05 · Disks, Memory and Packages: [../m02-l05-disks-memory-and-packages](../m02-l05-disks-memory-and-packages)
