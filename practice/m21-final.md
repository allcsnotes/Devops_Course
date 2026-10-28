# Module 21 · Final Practice Sheet: 75 DevOps Interview Questions

This is the last practice sheet of the course, and the talking half of your interview preparation. The doing half is the companion sheet, **[Module 21 take-home tasks](m21-take-home.md)**: 10 hands-on tasks of the kind companies send before an onsite.

The 75 questions cover the whole course, in course order: Linux, networking, Git, Docker, CI/CD and releases, cloud and infrastructure as code, Kubernetes, observability and SRE, security, and platform, cost and AI. A last group trains the behavioural round. 59 of the questions build on the 60 in [M21-L02](../interview/m21-l02-the-60-most-asked-devops-and-sre-questions/), often with a real output added or a trap fixed. 16 are new, marked **(new)**, many of them drawn from the capstone builds of Module 20.

**How to use it:**
- **Answer out loud, before you open anything.** Interviews are spoken. A sentence you can only recognise isn't a sentence you can say.
- Each question has a **type**, a **difficulty**, and the lessons that teach it (**Covered in**, the exact video folder names). If your answer was vague, rewatch that lesson and re-run its lab.
- The **hint** gives you a direction, not the answer. Open it only when you're stuck for more than a minute.
- The **model answer** is what a strong candidate says in one to two minutes, plus the reasoning behind it. Some answers end with **follow-ups**: the next question a good interviewer asks. Answer those out loud too.
- Question types: **Concept** (explain it), **Scenario** (what would you do), **Debug** (read a real output and say what's wrong), **Design** (pick an option and defend the trade-off), and **Behavioural** (a STAR story).

**Mock-interview mode.** Do one group at a time, with a timer, the way [M21-L01](../interview/m21-l01-how-devops-interviews-work/) describes a loop:
- Technical-screen questions (Concept, Easy and Medium): **60 seconds** each. Short and precise wins.
- Scenario and Debug questions: **3 minutes** each. Use the nine steps from [M21-L01](../interview/m21-l01-how-devops-interviews-work/): clarify, impact, observe, hypothesize, test, mitigate, fix, verify, prevent. Say what you'd check and why, not a list of tool names.
- Design questions: **5 minutes**. Requirements first, then the options, the choice and the trade-off you accept.
- Behavioural questions: **2 minutes**, in STAR shape (situation, task, action, result), plus one line of what you learned.
- Best of all, give the sheet to a friend. They play Rahul: they read the question, hold facts back until you ask for them, and stop you at the time limit. Record yourself once. You'll hear the "umm, I'd restart it" moments.

**About the outputs.** Every command and output in this sheet is real. Debug questions show a capture copied **unchanged** from a course video's recording, and name the lesson (linked to its folder in this repository) and the capture file. A few outputs were captured fresh for this sheet, in Docker, on 22 October 2026, in the labs of the take-home tasks; those say "captured for this sheet" and name the task. Long outputs are trimmed with `…`. Version facts are as checked in October 2026.

---

## Group A · Linux and the shell

### 1 · What is the difference between a hard link and a symbolic link?
**Concept · Easy** · Covered in: [M02-L01 - The Shell and the Filesystem](../linux/m02-l01-the-shell-and-the-filesystem/)

<details>
<summary>Hint</summary>

Think about what a directory entry points to: an inode, or a path.

</details>

<details>
<summary>Model answer</summary>

A hard link is a second name for the same inode, so it shares the same data and permissions, and the data lives until the last name is gone. It can't cross filesystems and can't point to a directory. A symbolic link is a small file of its own that holds a path. It can point anywhere, even across filesystems, but it breaks if the target moves or is deleted.

In the course you can see it in `ls -li`: the hard link has the **same inode number** and a link count of 2, the symlink has its own inode and an arrow:

```text
asha@web-01:~/site$ ls -li
total 12
19991 -rw-r--r-- 2 asha asha  191 Oct 20 09:03 app-hard.conf
32732 lrwxrwxrwx 1 asha asha    8 Oct 20 09:03 app-link.conf -> app.conf
19991 -rw-r--r-- 2 asha asha  191 Oct 20 09:03 app.conf
…
```
Real output: [M02-L01](../linux/m02-l01-the-shell-and-the-filesystem/) (the video's capture `h01-links.txt`).

**Follow-up:** why does nginx use symlinks in `sites-enabled`? Because switching a site on or off is creating or removing a link, while the one real file stays in `sites-available`. A dangling link (`find -xtype l`) is exactly the broken `robots.txt` of the Module 2 practice sheet.

</details>

### 2 · A web app can't write to its upload folder, and someone suggests `chmod 777`. What do you do?
**Scenario · Easy** · Covered in: [M02-L02 - Users, Groups and Permissions](../linux/m02-l02-users-groups-and-permissions/)

<details>
<summary>Hint</summary>

Two questions first: which user does the app run as, and who owns the folder?

</details>

<details>
<summary>Model answer</summary>

I find out which user the app runs as (`ps -o user`, or `User=` in its systemd unit) and who owns the folder (`ls -ld`). Then I grant exactly that: make the app user the owner, or put the app and the deploy user in one shared group with the setgid bit on the folder, and use 750 on folders and 640 on files. 777 lets every account on the server write there, including a compromised one, and that's how a planted web shell ends up in an uploads folder.

**Follow-up:** what do the three digits mean? Owner, group, others, each adding read 4, write 2 and execute 1. On a folder, execute means "may enter it".

</details>

### 3 · How do you stop a process safely?
**Concept · Easy** · Covered in: [M02-L03 - Processes, Signals and systemd](../linux/m02-l03-processes-signals-and-systemd/)

<details>
<summary>Hint</summary>

Which signal can a process catch, and which one can't it?

</details>

<details>
<summary>Model answer</summary>

I send SIGTERM first (`kill PID`), so the process can finish its work, remove lock files and exit. I wait a few seconds, and only if it won't stop do I send SIGKILL (`kill -9`), which can't be caught, so nothing gets cleaned up. If it's a service, I use `systemctl stop`, so systemd sends the signals, waits its timeout and records the result.

The worker in the course shows the difference a handler makes:

```text
asha@web-01:~$ kill 1508
asha@web-01:~$ worker: got SIGTERM, removing the lock file

[1]+  Done                    ./worker.sh
asha@web-01:~$ ls /tmp/upload-worker.lock
ls: cannot access '/tmp/upload-worker.lock': No such file or directory
```
Real output: [M02-L03](../linux/m02-l03-processes-signals-and-systemd/) (the video's capture `g02-worker-term.txt`).

</details>

### 4 · `ps` shows a process in state Z that `kill -9` can't remove. What is it, and how do you get rid of it?
**Debug · Medium** · Covered in: [M02-L03 - Processes, Signals and systemd](../linux/m02-l03-processes-signals-and-systemd/)

```text
asha@web-01:~$ kill -9 882
asha@web-01:~$ ps -o pid,ppid,stat,cmd
    PID    PPID STAT CMD
    261     260 S    -bash
    881     261 S    python3 zombie.py
    882     881 Z    [python3] <defunct>
    972     261 R+   ps -o pid,ppid,stat,cmd
```
Real output: [M02-L03](../linux/m02-l03-processes-signals-and-systemd/) (the video's capture `e04-zombie-b.txt`).

<details>
<summary>Hint</summary>

The process has already exited. Who hasn't done their job? Look at the PPID column.

</details>

<details>
<summary>Model answer</summary>

PID 882 is a zombie: it has already exited, but its parent, PID 881, never collected its exit status with `wait()`, so it stays in the process table with state Z and `<defunct>`. You can't kill what's already dead, so `kill -9` does nothing. The fix is the parent: fix its code so it reaps its children, or end it. In the same capture, `kill 881` ends the parent, init adopts and reaps the zombie, and both disappear from `ps`. A few zombies cost only a table entry; thousands can exhaust the PID limit.

**Follow-up:** why does this matter in containers? If your app is PID 1 and spawns children without reaping them, zombies pile up. `docker run --init` (tini) or a proper init as PID 1 reaps them.

</details>

### 5 · The disk is full. How do you find what is using it?
**Scenario · Medium** · Covered in: [M02-L05 - Disks, Memory and Packages](../linux/m02-l05-disks-memory-and-packages/), [M20-B03 - Troubleshooting Labs](../capstones/m20-b03-troubleshooting-labs/)

<details>
<summary>Hint</summary>

Three tools, and one case where two of them disagree.

</details>

<details>
<summary>Model answer</summary>

`df -h` tells me which filesystem is full. Then `du -sh` on its folders, sorted with `sort -h`, walks down to the biggest ones. If `df` says full but `du` can't find the space, a deleted file is still held open by a process, and `lsof +L1` shows it:

```text
asha@web-01:/data$ sudo lsof +L1
COMMAND  PID  USER   FD   TYPE DEVICE SIZE/OFF NLINK NODE NAME
python3 3031 allcs    4w   REG  0,136 40579072     0    9 /data/logs/api-debug.log (deleted)
```
Real output: [M02-L05](../linux/m02-l05-disks-memory-and-packages/) (the video's capture `e06-lsof.txt`).

To free that space, restart or reload the process holding it (or truncate it through `/proc/PID/fd/4`). And if there is space but writes still fail, check inodes with `df -i`. Next time, truncate a log instead of deleting it, and set up logrotate with a size limit and an alert at 80%.

**Follow-up:** in the [M20-B03](../capstones/m20-b03-troubleshooting-labs/) lab the full disk was a forgotten debug log that nobody held open. What would `lsof` print then? Nothing (exit code 1), so `truncate -s 0` frees the space at once. That's the take-home task 8 reference run.

</details>

### 6 · How would you find the top ten IP addresses hitting a web server?
**Concept · Easy** · Covered in: [M02-L04 - Text Processing](../linux/m02-l04-text-processing/)

<details>
<summary>Hint</summary>

Five small tools in one pipeline. Why do you need `sort` twice?

</details>

<details>
<summary>Model answer</summary>

```bash
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -n 10
```

`awk` takes the first field, the client address. `sort` puts identical addresses next to each other, because `uniq -c` only counts **adjacent** duplicates. The second `sort -rn` orders by the count, largest first, and `head` keeps ten. Behind a load balancer the first field is the balancer's address, so I'd use the `X-Forwarded-For` field the proxy logs instead.

</details>

### 7 · What does `set -euo pipefail` do, and is it enough?
**Concept · Medium** · Covered in: [M03-L02 - Robust Scripts](../scripts/m03-l02-robust-scripts/)

<details>
<summary>Hint</summary>

When does `-e` not fire?

</details>

<details>
<summary>Model answer</summary>

`-e` exits when a command fails, `-u` makes an unset variable an error, and `pipefail` makes a pipeline fail if any stage fails, not only the last one. It's not enough on its own: `-e` is ignored inside `if` and `while` conditions and in `&&` and `||` lists, and a failure inside a command substitution can be swallowed. So I still check the important commands explicitly, quote every variable, clean up with `trap ... EXIT`, and run shellcheck in CI.

</details>

### 8 · (new) Shellcheck flags this line in a health-check script. Is it a real bug?
**Debug · Medium** · Covered in: [M03-L02 - Robust Scripts](../scripts/m03-l02-robust-scripts/), [M03-B01 - Build a Server Health-Check Toolkit](../scripts/m03-b01-build-a-server-health-check-toolkit/)

```text
$ shellcheck -x healthcheck.sh tests/run.sh; echo "exit $?"

In healthcheck.sh line 84:
  is_int "$WARN" && is_int "$CRIT" || die "thresholds must be whole numbers"
                 ^-- SC2015 (info): Note that A && B || C is not if-then-else. C may run when A is true.
…
exit 1
```
Captured for this sheet: the first draft of take-home task 1, `koalaman/shellcheck:v0.11.0`.

<details>
<summary>Hint</summary>

When does `die` run? Try every combination of A and B.

</details>

<details>
<summary>Model answer</summary>

`A && B || C` runs C when A fails, but **also** when A succeeds and B fails. Here both cases should die, so this particular line happens to behave correctly, but the pattern is a trap: as soon as B is something like `echo ok` or `mv`, C runs after a success. Shellcheck rates it "info", not "error", and still exits 1, so a CI gate fails on it. The fix is to say what you mean:

```bash
if ! is_int "$WARN" || ! is_int "$CRIT"; then die "thresholds must be whole numbers"; fi
```

After that change the same run printed `exit 0`. I'd keep shellcheck as a required check, and fix findings instead of disabling them, or disable one with a `# shellcheck disable=SC....` comment that says why.

</details>

---

## Group B · Networking

### 9 · How many usable hosts fit in a /27, and on AWS?
**Concept · Easy** · Covered in: [M04-L01 - IP Addresses, Subnets and CIDR](../networking/m04-l01-ip-addresses-subnets-and-cidr/), [M10-L03 - VPC Networking](../cloud/m10-l03-vpc-networking/)

<details>
<summary>Hint</summary>

32 minus the prefix gives the host bits.

</details>

<details>
<summary>Model answer</summary>

A /27 leaves 32 - 27 = 5 host bits, so 2^5 = 32 addresses. Minus the network and broadcast addresses, that's 30 usable hosts:

```text
asha@web-01:~$ ipcalc -nb 10.0.1.0/27
…
Network:   10.0.1.0/27
HostMin:   10.0.1.1
HostMax:   10.0.1.30
Broadcast: 10.0.1.31
Hosts/Net: 30                    Class A, Private Internet
```
Real output: [M04-L01](../networking/m04-l01-ip-addresses-subnets-and-cidr/) (the video's capture `k01-27.txt`).

On AWS it's 27, because AWS reserves 5 addresses in every subnet: the network address, the next three (router, DNS, reserved) and the last one.

</details>

### 10 · You changed a DNS record, but some users reach the old server for hours. Why, and how should the change have been done?
**Scenario · Medium** · Covered in: [M04-L02 - DNS in Practice](../networking/m04-l02-dns-in-practice/)

```text
asha@web-01:~$ dig api.allcsvideos.test
…
;; ANSWER SECTION:
api.allcsvideos.test.   86392   IN      A       10.0.53.21
…
;; SERVER: 10.0.53.53#53(10.0.53.53) (UDP)
```
Real output: [M04-L02](../networking/m04-l02-dns-in-practice/) (the video's capture `f02-dig-again.txt`) (the resolver's cached answer, eight seconds after the first query: the TTL counts down from 86400).

<details>
<summary>Hint</summary>

What does the second column of the answer section count?

</details>

<details>
<summary>Model answer</summary>

Resolvers cache an answer for its TTL. The 86392 here is the seconds left of a one-day TTL, so this resolver keeps handing out the old address for almost a day, whatever the authoritative server now says. Users behind other resolvers see the change at different times. The safe way: lower the TTL (say to 300 s) at least one old TTL before the move, change the record, check it with `dig @the-authoritative-server` and with a public resolver, keep the old server up until its traffic drains, then raise the TTL again.

</details>

### 11 · What happens when you open https://allcsvideos.com in a browser?
**Concept · Medium** · Covered in: [M04-L02 - DNS in Practice](../networking/m04-l02-dns-in-practice/), [M04-L03 - Ports, TCP and Firewalls](../networking/m04-l03-ports-tcp-and-firewalls/), [M04-L04 - HTTP, TLS and Certificates](../networking/m04-l04-http-tls-and-certificates/)

<details>
<summary>Hint</summary>

Name, connection, encryption, request. Then what's behind the server's address.

</details>

<details>
<summary>Model answer</summary>

DNS turns the name into an address: the browser's cache, the OS resolver, then a recursive resolver that asks the root, the `.com` servers and the domain's authoritative servers. The browser opens a TCP connection to port 443 (SYN, SYN-ACK, ACK). A TLS 1.3 handshake follows: the server sends its certificate chain, the browser checks it up to a trusted root, checks the name and the dates, and both sides derive session keys. Then the HTTP request travels encrypted, usually to a load balancer or reverse proxy, which forwards it to an app server, which may call a cache and a database before the response comes back.

**Follow-up:** where can it go wrong, and which tool shows it? DNS (`dig`), the path (`traceroute`, knowing ICMP may be blocked), the port (`nc -zv`, `curl -v`), TLS (`openssl s_client`), HTTP (`curl -w` timings), then the proxy and app logs.

</details>

### 12 · Connection refused versus connection timed out: what is the difference?
**Debug · Medium** · Covered in: [M04-L03 - Ports, TCP and Firewalls](../networking/m04-l03-ports-tcp-and-firewalls/)

Two captures on the server, port 9000, from the same client:

```text
asha@web-01:~$ sudo tcpdump -n -t -i eth0 tcp port 9000
…
IP 10.0.1.10.34940 > 10.0.1.11.9000: Flags [S], seq 2043356553, win 64240, options [mss 1460,sackOK,
TS val 447743717 ecr 0,nop,wscale 7], length 0
IP 10.0.1.11.9000 > 10.0.1.10.34940: Flags [R.], seq 0, ack 2043356554, win 0, length 0
```
Real output: [M04-L03](../networking/m04-l03-ports-tcp-and-firewalls/) (the video's capture `e06-refused.txt`).

```text
asha@web-01:~$ sudo tcpdump -n -t -i eth0 tcp port 9000
…
IP 10.0.1.10.42574 > 10.0.1.11.9000: Flags [S], seq 146468316, win 64240, options [mss 1460,sackOK,T
S val 447785464 ecr 0,nop,wscale 7], length 0
IP 10.0.1.10.42574 > 10.0.1.11.9000: Flags [S], seq 146468316, win 64240, options [mss 1460,sackOK,T
S val 447786522 ecr 0,nop,wscale 7], length 0
…
5 packets captured
```
Real output: [M04-L03](../networking/m04-l03-ports-tcp-and-firewalls/) (the video's capture `f09-timeout.txt`).

<details>
<summary>Hint</summary>

Look at what comes back after the `[S]`, if anything.

</details>

<details>
<summary>Model answer</summary>

In the first capture the SYN reached the host and the kernel answered at once with a reset (`[R.]`): nothing listens on that port. That's "connection refused", and it's fast. In the second, the same SYN is sent again and again with the same sequence number and nothing ever comes back: a firewall or security group drops the packet silently, and the client retries until it gives up with "timed out". So for refused, I check on the server whether the app runs and what it listens on (`ss -tlnp`: is it bound to 127.0.0.1 instead of 0.0.0.0?). For a timeout, I check the firewall rules, security groups, network ACLs and routes along the path.

</details>

### 13 · What is the difference between a 502 and a 504?
**Concept · Easy** · Covered in: [M04-L05 - The Troubleshooting Toolbox](../networking/m04-l05-the-troubleshooting-toolbox/), [Module 13 practice sheet](m13-kubernetes.md)

<details>
<summary>Hint</summary>

Who sends both of them?

</details>

<details>
<summary>Model answer</summary>

Both come from the proxy or gateway, not from the app. A 502 Bad Gateway means the proxy couldn't get a valid answer from its upstream: the connection was refused, reset, or the reply was garbage. A 504 Gateway Timeout means the upstream didn't answer in time, for example after nginx's `proxy_connect_timeout` or `proxy_read_timeout`. Either way the proxy's error log names the upstream and the reason. In the Module 13 practice sheet a wrong Service port made nginx wait 3 s for `catalog:80` and answer 504.

</details>

### 14 · A service is unreachable. Which tools do you use, and in what order?
**Scenario · Medium** · Covered in: [M04-L05 - The Troubleshooting Toolbox](../networking/m04-l05-the-troubleshooting-toolbox/)

<details>
<summary>Hint</summary>

Outside-in, one layer at a time, and each tool answers one question.

</details>

<details>
<summary>Model answer</summary>

First I reproduce it as a user with `curl -v`, so I know the exact error. Then I go layer by layer, each check read-only: `dig` for the name (right address? from which resolver?), `ping` or `traceroute` for the path (knowing ICMP is often blocked), `nc -zv host port` or `curl` for the TCP port (refused or timeout?), `openssl s_client -connect host:443 -servername host` for TLS (chain, name, dates), `curl -w` with timings for HTTP (where does the time go?), and finally the proxy and app logs. I stop at the first layer that fails, because everything above it is noise.

</details>

### 15 · (new) `curl` exits with code 60 against your own site. Find the cause from these outputs.
**Debug · Medium** · Covered in: [M04-L04 - HTTP, TLS and Certificates](../networking/m04-l04-http-tls-and-certificates/), [M20-B03 - Troubleshooting Labs](../capstones/m20-b03-troubleshooting-labs/)

```text
asha@ops:~$ curl -sS -o /dev/null https://www.allcsvideos.test/api/courses
curl: (60) SSL certificate OpenSSL verify result: certificate has expired (10)
…
asha@ops:~$ openssl s_client -connect www.allcsvideos.test:443 -servername www.allcsvideos.test </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
subject=CN=www.allcsvideos.test
issuer=CN=allcsvideos LAB CA
notBefore=Jul 23 21:04:15 2026 GMT
notAfter=Oct 21 20:04:15 2026 GMT
asha@ops:~$ date -u
Wed Oct 21 21:04:21 UTC 2026
```
Real output: [M20-B03](../capstones/m20-b03-troubleshooting-labs/) (the video's capture `s3-a.txt`) and `s3-b.txt` (a staged fault).

<details>
<summary>Hint</summary>

Compare two of the lines with the clock.

</details>

<details>
<summary>Model answer</summary>

The certificate's `notAfter` is 20:04:15 UTC, and the clock says 21:04:21: it expired an hour ago, so every client refuses the TLS handshake (curl exit 60, browsers show a full-page warning). The name and the issuer are fine, so it's not a mismatch or an unknown CA. Mitigate: issue a new certificate, run `nginx -t`, then `systemctl reload nginx` (a reload, so no connection is dropped), and verify from outside with the same `openssl` command and `curl`. Prevent: the renewal job clearly didn't run, so make renewal automatic (certbot or cert-manager), alert on its failure, and add an alert on certificate expiry under 21 days, measured from outside, like a user.

**Follow-up:** why check the clock at all? Because a server with a wrong clock produces the same error with a perfectly valid certificate.

</details>

---

## Group C · Git

### 16 · Merge or rebase: what is the difference, and when do you use each?
**Concept · Medium** · Covered in: [M05-L03 - Merge, Rebase and Fixing Mistakes](../git/m05-l03-merge-rebase-and-fixing-mistakes/)

<details>
<summary>Hint</summary>

Which one changes commit hashes?

</details>

<details>
<summary>Model answer</summary>

A merge joins two histories with a merge commit and rewrites nothing. A rebase replays my commits on top of the new base, one by one, so the history is linear, but every replayed commit gets a new hash. So I rebase only my own branch, before I share it, to tidy it up or catch up with main, and I never rebase a branch others have pulled. For shared branches, merge.

**Follow-up:** you rebased a branch you had already pushed. How do you push it? `git push --force-with-lease`: it refuses to overwrite commits on the remote that you haven't seen, unlike `--force`.

</details>

### 17 · What is the difference between `git reset` and `git revert`, and how do you undo a bad reset?
**Scenario · Medium** · Covered in: [M05-L03 - Merge, Rebase and Fixing Mistakes](../git/m05-l03-merge-rebase-and-fixing-mistakes/), [Module 05 practice sheet](m05-git.md)

<details>
<summary>Hint</summary>

One rewrites history, one adds to it. And Git keeps a diary of where HEAD has been.

</details>

<details>
<summary>Model answer</summary>

Reset moves the branch pointer back and rewrites history, so I use it only on local commits nobody else has. Revert adds a new commit that undoes an old one, so it's the safe way to undo anything already pushed. And if a reset goes too far, the reflog still knows the old commits:

```text
asha@lab:~/allcsvideos-ops$ git reflog -3
679738c (HEAD -> main, origin/main) HEAD@{0}: reset: moving to HEAD~3
a6635f5 HEAD@{1}: commit: experiment: also check /tmp
ab40548 HEAD@{2}: commit: hc.conf: CRIT at load 4 per CPU
asha@lab:~/allcsvideos-ops$ git reset --hard HEAD@{1}
HEAD is now at a6635f5 experiment: also check /tmp
…
```
Real output: [M05-L03](../git/m05-l03-merge-rebase-and-fixing-mistakes/) (the video's capture `i03-reflog.txt`).

The rule that decides almost every Git rescue: has it been pushed? Not pushed: amend, reset, rebase. Pushed: revert. Lost: the reflog.

</details>

### 18 · GitFlow or trunk-based development: which would you choose?
**Design · Medium** · Covered in: [M05-L02 - Branching Strategies](../git/m05-l02-branching-strategies/)

<details>
<summary>Hint</summary>

It depends on how the software ships.

</details>

<details>
<summary>Model answer</summary>

It depends on how we ship. For a web service deployed continuously, like allcsvideos, trunk-based: short-lived branches merged at least daily, feature flags for unfinished work, and fast CI, because small daily merges keep integration cheap and conflicts small. GitFlow, or release branches, fit software where several shipped versions must be maintained at the same time, like a mobile app or an installed product, where you patch 1.3 while 1.4 is in development. The trade-off I'd name: trunk-based needs good tests and flags; GitFlow needs more merging and slows feedback.

</details>

### 19 · How do you stop a bad change from reaching main?
**Concept · Easy** · Covered in: [M05-L04 - The Pull-Request Workflow](../git/m05-l04-the-pull-request-workflow/)

<details>
<summary>Hint</summary>

Protection, people and machines.

</details>

<details>
<summary>Model answer</summary>

Protect main so nobody pushes to it directly, not even admins. Require a pull request with at least one approval, and code owners for sensitive paths like the deploy config. Require the CI checks to pass on a branch that's up to date with main, so the code that merges is the code that was tested. Dismiss stale approvals when new commits arrive. And keep pull requests small, because reviewers can't catch what they can't read.

</details>

---

## Group D · Docker and containers

### 20 · What is a container, and how is it different from a virtual machine?
**Concept · Easy** · Covered in: [M06-L01 - VMs vs Containers](../docker/m06-l01-vms-vs-containers/)

<details>
<summary>Hint</summary>

Three Linux features, and one kernel.

</details>

<details>
<summary>Model answer</summary>

A container is an ordinary Linux process, isolated by namespaces (its own view of PIDs, network, mounts, hostname, users), limited by cgroups (CPU, memory, PIDs), with its own root filesystem from an image. Containers share the host kernel, so they start in a fraction of a second and pack densely. A VM boots its own kernel on virtual hardware, which is heavier and slower to start, but it's a stronger isolation boundary. That's why you can't run a Windows container on a Linux kernel, and why Docker Desktop on a Mac runs a small Linux VM.

</details>

### 21 · Image versus container, and why does changing one Dockerfile line rebuild everything after it?
**Concept · Medium** · Covered in: [M06-L02 - Images, Layers and Registries](../docker/m06-l02-images-layers-and-registries/), [M06-L04 - The Dockerfile, Line by Line](../docker/m06-l04-the-dockerfile-line-by-line/)

<details>
<summary>Hint</summary>

Each layer is built on top of the one before it.

</details>

<details>
<summary>Model answer</summary>

An image is a read-only stack of layers plus a config (entrypoint, env, user); a container is a running process with a thin writable layer on top of that stack. Each instruction's layer depends on everything before it, so when one instruction changes, the cache for it and every instruction after it is invalid. So copy and install the dependency files first (`COPY requirements.txt` then `pip install`), and copy the source last: a code change then rebuilds only the last layers.

</details>

### 22 · What is the difference between CMD and ENTRYPOINT, and why use exec form?
**Concept · Medium** · Covered in: [M06-L04 - The Dockerfile, Line by Line](../docker/m06-l04-the-dockerfile-line-by-line/)

<details>
<summary>Hint</summary>

What becomes PID 1 with shell form?

</details>

<details>
<summary>Model answer</summary>

ENTRYPOINT is the fixed program, and CMD gives its default arguments, which `docker run IMAGE args` replace. Exec form (`["uvicorn", "app.main:app"]`) runs the program directly as PID 1. Shell form (`CMD uvicorn app.main:app`) wraps it in `/bin/sh -c`, so the shell is PID 1, SIGTERM goes to the shell, and the app never hears it. hadolint flags shell form as DL3025, and take-home task 2 shows the cost: the starter image with a shell-form CMD took 10 s to stop and exited with 137.

</details>

### 23 · A container takes ten seconds to stop and exits with code 137. What is going on?
**Debug · Medium** · Covered in: [M06-L03 - Running Containers](../docker/m06-l03-running-containers/), [M14-L06 - Troubleshooting Kubernetes](../k8s/m14-l06-troubleshooting-kubernetes/)

```text
$ time docker stop stubborn
stubborn

real	0m10.125s
…
$ docker inspect --format 'exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' stubborn
exit=137 oom=false
```
Real output: [M06-L03](../docker/m06-l03-running-containers/) (the video's capture `i03.txt`) (the container ran with `--stop-timeout 10`).

<details>
<summary>Hint</summary>

137 = 128 + ? And what does `oom=false` rule out?

</details>

<details>
<summary>Model answer</summary>

137 is 128 + 9: the process was killed by SIGKILL. Out of memory is one cause, but `OOMKilled` is false here. The 10 seconds give it away: `docker stop` sent SIGTERM, waited out the stop timeout, then sent SIGKILL. So the app never handled SIGTERM, usually because it runs as PID 1 behind a shell-form CMD, or because PID 1 gets no default signal handlers. Fix: exec form, a SIGTERM handler that drains and exits, or `docker run --init`. In Kubernetes the same thing costs `terminationGracePeriodSeconds`, 30 s by default, on every pod of every rollout.

**Trap:** don't quote "10 seconds" as Docker's default without checking. The docs give 10 s for Linux containers, but the Docker Desktop in this course gives new containers a stop timeout of 1 s, which is why the lesson set it explicitly.

**Follow-up:** how do you tell an OOM kill from a slow stop? `docker inspect` shows `State.OOMKilled: true`; in Kubernetes `kubectl describe` shows `Last State: Terminated, Reason: OOMKilled` (question 43).

</details>

### 24 · How do you keep a containerised database's data safe? Volume or bind mount?
**Concept · Easy** · Covered in: [M06-L05 - Volumes and Bind Mounts](../docker/m06-l05-volumes-and-bind-mounts/), [M17-L04 - Chaos Engineering and Disaster Recovery](../observability/m17-l04-chaos-engineering-and-disaster-recovery/)

<details>
<summary>Hint</summary>

Where does the data live, and is it a backup?

</details>

<details>
<summary>Model answer</summary>

Database data goes in a named volume, which Docker manages and which outlives any container. A bind mount maps a host path I choose, which suits code in development and read-only config. With the current PostgreSQL 18 images, mount the volume at `/var/lib/postgresql`, not at the old `.../data` path, or the container exits. And a volume is not a backup: it lives on the same disk, so dump with the database's own tool or archive WAL off the host, and test the restore on a schedule.

</details>

### 25 · Two containers: the app can't reach the database at `localhost`. Why?
**Debug · Easy** · Covered in: [M06-L06 - Container Networking](../docker/m06-l06-container-networking/), [M07-L02 - Docker Compose](../docker/m07-l02-docker-compose/)

<details>
<summary>Hint</summary>

Whose localhost is it?

</details>

<details>
<summary>Model answer</summary>

Each container has its own network namespace, so `localhost` inside the app container is the app container itself, and nothing listens on 5432 there. Put both containers on a user-defined network (Compose creates one per project), where Docker's embedded DNS resolves container and service names, and point the app at `db:5432`. Publish only the front end to the host, and keep the database on an internal network, like the backend network of take-home task 3.

</details>

### 26 · How would you make a slow, one-gigabyte image small, fast to build and clean in a scan?
**Scenario · Medium** · Covered in: [M07-L01 - Small, Fast Images](../docker/m07-l01-small-fast-images/), [M07-L03 - Image Security](../docker/m07-l03-image-security/), [M18-L01 - Shift Left](../security/m18-l01-shift-left/)

<details>
<summary>Hint</summary>

Stages, order, cache, base. And what is in the image that the app never uses?

</details>

<details>
<summary>Model answer</summary>

A multi-stage build, so only the runtime and the app ship: no compilers, no test tools, no source control. Order the steps from least to most often changing, dependencies before source, and add a BuildKit cache mount for the package manager. Pick the smallest base the team can still debug and patch (slim, Alpine or distroless). Then remove what the app never uses at run time, and measure size, rebuild time and scan results at every step.

That last step matters for scans. Trivy on take-home task 2's starter image, a single-stage `python:3.13.16-slim`, found five fixable HIGH or CRITICAL issues, all in packages the app never imports:

```text
Python (python-pkg)
===================
Total: 5 (HIGH: 4, CRITICAL: 1)
…
│ certifi    │ GHSA-6q48-6c7w-9gw2 │ CRITICAL │ fixed  │ 2026.6.17         │ 2026.10.19    │ …
│ msgpack    │ GHSA-6v7p-g79w-8964 │ HIGH     │        │ 1.1.2             │ 1.2.1         │ …
│ setuptools │ CVE-2025-47273      │          │        │ 70.3.0            │ 78.1.1        │ …
│ urllib3    │ CVE-2026-97687      │          │        │ 2.7.0             │ 2.8.0         │ …
```
Captured for this sheet: take-home task 2, `aquasec/trivy:0.76.0` (by digest), 22 October 2026. Results change as the database does.

They are libraries vendored inside pip itself. The multi-stage image uninstalls pip in the runtime stage, and the same scan reports 0. Its content size went from 64.5 MB to 48.7 MB.

</details>

---

## Group E · CI/CD and releases

### 27 · What is continuous integration, and how can you tell whether a team really does it?
**Concept · Easy** · Covered in: [M08-L01 - What CI Is](../ci/m08-l01-what-ci-is/)

<details>
<summary>Hint</summary>

A CI server is not CI.

</details>

<details>
<summary>Model answer</summary>

CI means everyone merges into main at least daily, and every commit triggers an automated build and tests that answer in about ten minutes. To tell whether a team really does it, I'd check that branches live a day or two, not weeks; that a broken main is fixed or reverted within minutes, not left red; and that people trust the tests enough not to re-run them until green. Having Jenkins or GitHub Actions installed isn't CI if branches live for a month.

</details>

### 28 · Walk me through a GitHub Actions workflow. What runs where?
**Concept · Medium** · Covered in: [M08-L02 - GitHub Actions Anatomy](../ci/m08-l02-github-actions-anatomy/), [M08-L03 - Build, Test and Lint](../ci/m08-l03-build-test-and-lint/)

<details>
<summary>Hint</summary>

Events, jobs, runners, steps, and what you pin.

</details>

<details>
<summary>Model answer</summary>

A workflow is a YAML file in `.github/workflows/`; its `on:` key lists the events that start it (push, pull request, schedule, manual dispatch). Jobs run in parallel, each on a fresh runner chosen by `runs-on`, unless `needs:` orders them. Each job runs its steps in order: shell commands with `run:`, or actions with `uses:`. Jobs share nothing unless I pass outputs or artifacts. For safety I set `permissions:` to the minimum, pin third-party actions to a full commit SHA, and add `timeout-minutes` and `concurrency` so stale runs get cancelled.

**Follow-up:** in take-home task 4 the same `.github/workflows/ci.yml` ran unchanged on Gitea Actions: lint, test and scan in parallel, and build only after all three passed.

</details>

### 29 · Continuous delivery versus continuous deployment, and how do you promote a release?
**Concept · Medium** · Covered in: [M09-L01 - Delivery vs Deployment](../ci/m09-l01-delivery-vs-deployment/), [M19-L03 - Multi-Environment and Multi-Account Strategy](../platform/m19-l03-multi-environment-and-multi-account-strategy/)

<details>
<summary>Hint</summary>

Who presses the button? And what exactly moves between environments?

</details>

<details>
<summary>Model answer</summary>

With continuous delivery every green change is releasable, and production is a one-click decision by a person. Continuous deployment ships every green change automatically. Either way, I build the image once and promote that same digest from staging to production, never a rebuild, so production runs exactly the bytes that staging tested.

**Follow-up:** why not just deploy `:latest`? It's a moving label: you can't tell what runs, two nodes can pull two different images, and you can't roll back to "the old latest".

</details>

### 30 · (new) Why "never rebuild to promote"? The commit didn't change.
**Debug · Medium** · Covered in: [M19-L03 - Multi-Environment and Multi-Account Strategy](../platform/m19-l03-multi-environment-and-multi-account-strategy/), [M09-L04 - Versioning and Rollback](../ci/m09-l04-versioning-and-rollback/)

The same commit `d98b6d6` (tag v1.9.0), built twice by the same CI box:

```text
ci@build-01:/work/allcsvideos-api$ build-image 1.9.0
pushed localhost:19302/allcsvideos/api:1.9.0
digest sha256:da4ffaa97e80f2892a7113eb7e90103ac6f2aed6efb1ecb29bee9f7b309a0086
```
Real output: [M19-L03](../platform/m19-l03-multi-environment-and-multi-account-strategy/) (the video's capture `b01-build.txt`).

```text
ci@build-01:/work/allcsvideos-api$ git checkout -q v1.9.0 && git log --oneline -1
d98b6d6 (HEAD, tag: v1.9.0) api 1.9.0: faster course search
ci@build-01:/work/allcsvideos-api$ build-image 1.9.0
pushed localhost:19302/allcsvideos/api:1.9.0
digest sha256:66400b74fc4d25c3ccd8dbb932aa5d0646bb34b14cf633206f98d44225acbb59
```
Real output: [M19-L03](../platform/m19-l03-multi-environment-and-multi-account-strategy/) (the video's capture `b05-rebuild.txt`).

<details>
<summary>Hint</summary>

Compare the digests. Then ask what the tag 1.9.0 points to now.

</details>

<details>
<summary>Model answer</summary>

Same commit, two different digests. Here the build time baked into the image was enough to change it; in real builds, a base image that moved, a dependency that resolved to a newer patch, or a different builder does the same. And the push silently moved the tag `1.9.0` to the new image. So a rebuild is a new, untested artifact: if production gets a rebuild, staging tested something else. The lesson's environments survived because each overlay pinned the **digest**, not the tag. The rules: build once, record the digest, promote that digest through pull requests to each environment, and make registry tags immutable where the registry supports it.

</details>

### 31 · Rolling, blue-green or canary: how do you choose?
**Design · Medium** · Covered in: [M09-L02 - Deployment Strategies](../ci/m09-l02-deployment-strategies/), [M15-B01 - Deploy allcsvideos to EKS with Helm and Argo CD](../k8s/m15-b01-deploy-allcsvideos-to-eks-with-helm-and-argo-cd/)

<details>
<summary>Hint</summary>

Cost, blast radius, rollback speed.

</details>

<details>
<summary>Model answer</summary>

Rolling replaces instances a few at a time: cheap and the default in Kubernetes, but old and new run side by side, and a bad version reaches everyone by the end. Blue-green runs a full second environment and switches all traffic at once, so rollback is one switch, at the cost of double capacity and 100% exposure after the switch. Canary sends a small slice of traffic to the new version and lets metrics decide each next step, so a bad release hurts few users, but it needs good metrics and either enough replicas or a traffic router for precise weights. I'd use rolling with readiness probes for low-risk changes, and canaries gated on the SLO for risky ones. Whatever the strategy, schema changes must stay backward compatible, because old and new versions overlap.

</details>

### 32 · What is the difference between deploying and releasing, and how do feature flags help?
**Concept · Easy** · Covered in: [M09-L03 - Feature Flags](../ci/m09-l03-feature-flags/)

<details>
<summary>Hint</summary>

One puts code on servers, the other puts features in front of users.

</details>

<details>
<summary>Model answer</summary>

Deploying puts a build on servers; releasing exposes a feature to users. With flags, code ships dark and is turned on at runtime: for staff first, then a percentage, with no redeploy, and turned off just as fast. An ops flag works as a kill switch for a misbehaving dependency, like the Course Copilot kill switch of the Module 17 game day. Every flag needs an owner and an expiry date, or the codebase fills with dead branches nobody dares to remove.

</details>

### 33 · How do you make a release that changes the database safe to roll back?
**Design · Hard** · Covered in: [M09-L04 - Versioning and Rollback](../ci/m09-l04-versioning-and-rollback/)

<details>
<summary>Hint</summary>

Three phases, spread over more than one release.

</details>

<details>
<summary>Model answer</summary>

Expand, migrate, contract. First expand: add the new column or table in a way the old release still works with (nullable, or with a default). Then release code that writes both and reads the new one, and migrate the data in batches. Only a release later, when nothing reads the old column, contract: drop it. Then any rollback is simply the previous image digest, because the schema works for both versions. Take a backup before any destructive step, and know that tools like `flyway undo` aren't a plan: in the course it isn't even available in the free edition.

</details>

### 34 · How do you measure software delivery performance?
**Concept · Easy** · Covered in: [M01-L01 - What is DevOps](../setup/m01-l01-what-is-devops/), [M20-L01 - Designing a Production Delivery Platform](../capstones/m20-l01-designing-a-production-delivery-platform/)

<details>
<summary>Hint</summary>

Five metrics, two groups.

</details>

<details>
<summary>Model answer</summary>

With the five DORA metrics (dora.dev, checked in 2026). Throughput: change lead time, deployment frequency, and failed deployment recovery time. Instability: change fail rate and deployment rework rate. I track them as trends per team, compared with the team's own past, and never as targets for individuals, because a measure that becomes a target stops measuring.

**Follow-up:** what happened to MTTR? DORA replaced it with failed deployment recovery time in 2023, and added deployment rework rate in 2024.

</details>

### 35 · (new) The migration gate said PASS, but the per-request log shows 6 failed requests. What went wrong?
**Debug · Hard** · Covered in: [M20-B01 - Zero-Downtime Migration from VMs to Kubernetes](../capstones/m20-b01-zero-downtime-migration-from-vms-to-kubernetes/), [M17-L01 - SLIs, SLOs and Error Budgets](../observability/m17-l01-slis-slos-and-error-budgets/)

```text
asha@ops:~/migration$ gate.sh 60
SLO gate, last 60 s     requests   errors  over 250 ms
  Kubernetes pool           1219        0            0   ok
  all students              1797        0            0   ok
PASS (errors <= 0.1 %, slow <= 1 %)
```
Real output: [M20-B01](../capstones/m20-b01-zero-downtime-migration-from-vms-to-kubernetes/) (the video's capture `c38-gatebug.txt`).

```text
asha@ops:~/migration$ report.py b2
run b2: 6,001 requests in 2m 29s (40.0 per second)
pool    requests  failed   p95 ms   p99 ms
vm         4,668       0     10.3     37.4
k8s        1,333       6     17.4     57.8
all        6,001       6     12.3     42.3
…
failed requests by pool, status and route:
  k8s  502  courses       4
  k8s  502  me            2
```
Real output: [M20-B01](../capstones/m20-b01-zero-downtime-migration-from-vms-to-kubernetes/) (the video's capture `c39-gatebug.txt`) (a staged fault: a rollout without readiness probe and preStop hook).

<details>
<summary>Hint</summary>

The gate reads error counters from Prometheus. What does `rate()` return for a counter that didn't exist before the first error?

</details>

<details>
<summary>Model answer</summary>

Two problems, one hidden behind the other. The 502s are real: the rollout had no readiness probe and no preStop delay, so new pods got traffic before they listened, and old pods stopped listening while kube-proxy still sent them requests. But the gate reported 0 errors, because the error counter series was only created by the first error, and a rate over a series that just appeared shows nothing for that window. A gate that can't see errors is worse than no gate, because it turns a failure into a confident PASS. The fix in the build: create every counter at zero when the test starts, test the gate itself with a fault you know is there (it then failed, as it should, estimating 4 errors where the exact log said 2, because Prometheus extrapolates), and put the readiness probe and preStop hook back. The re-run: 6,001 requests, 0 failed, and the gate and the log agreed.

</details>

---

## Group F · Cloud, infrastructure as code and configuration

### 36 · What makes a subnet public or private on AWS?
**Concept · Easy** · Covered in: [M10-L03 - VPC Networking](../cloud/m10-l03-vpc-networking/)

<details>
<summary>Hint</summary>

Not its name, and not a checkbox on the subnet.

</details>

<details>
<summary>Model answer</summary>

Only its route table. A public subnet routes 0.0.0.0/0 to an internet gateway; a private subnet routes it to a NAT gateway, for outbound-only traffic; an isolated subnet keeps just the local route. Then security groups chain by reference, load balancer to app to database, so the database accepts 5432 only from the app's security group. Worth knowing for the bill: NAT gateways charge per hour and per gigabyte processed.

</details>

### 37 · How do you give an application on EC2 access to an S3 bucket?
**Scenario · Easy** · Covered in: [M10-L02 - IAM](../cloud/m10-l02-iam/), [M15-L04 - Managed Kubernetes on EKS](../k8s/m15-l04-managed-kubernetes-on-eks/)

<details>
<summary>Hint</summary>

No keys on the box.

</details>

<details>
<summary>Model answer</summary>

Never with access keys on the instance. I create an IAM role that only the EC2 service can assume, attach it through an instance profile, and give it a policy for just the actions it needs on that one bucket (for example `s3:GetObject` on `arn:aws:s3:::bucket/*`). The SDK picks up temporary credentials from the instance metadata service, and they rotate on their own. I require IMDSv2. On EKS the same idea is IRSA or EKS Pod Identity, scoped to one ServiceAccount.

</details>

### 38 · Design a web tier that survives losing an instance, or a whole availability zone.
**Design · Medium** · Covered in: [M10-L04 - Compute](../cloud/m10-l04-compute/), [M10-L05 - Storage and Databases](../cloud/m10-l05-storage-and-databases/)

<details>
<summary>Hint</summary>

Spread, check, replace, and the database.

</details>

<details>
<summary>Model answer</summary>

An Auto Scaling group from a versioned launch template, in private subnets across at least two availability zones, behind an Application Load Balancer whose health checks call a real health endpoint. An unhealthy instance is replaced; a lost zone's traffic shifts to the others, so each zone needs headroom (N+1). Target tracking scales between a minimum and a maximum. Servers stay stateless: sessions in Redis or a signed cookie, files in S3.

**Follow-up:** and the database? RDS Multi-AZ: a synchronous standby in another zone with automatic failover, plus automated backups for point-in-time recovery, and a restore drill.

</details>

### 39 · Why does Terraform have a plan step?
**Concept · Easy** · Covered in: [M11-L01 - Why IaC](../terraform/m11-l01-why-iac/)

<details>
<summary>Hint</summary>

Declarative tools compute the steps for you. Who checks them?

</details>

<details>
<summary>Model answer</summary>

Terraform is declarative: I describe the end state, and it diffs that against its state and the real infrastructure to compute the steps. The plan shows that diff before anything changes: `+` create, `~` update in place, `-` destroy, `-/+` replace. The team reviews it in the pull request, and the pipeline applies exactly that saved plan, so what was approved is what happens. The line to look for first is "Plan: X to add, Y to change, Z to destroy", and any unexpected destroy or replace.

</details>

### 40 · What is Terraform state, and how do you manage it in a team?
**Debug · Medium** · Covered in: [M11-L03 - State](../terraform/m11-l03-state/), [M11-L05 - Environments and Pipelines](../terraform/m11-l05-environments-and-pipelines/)

A colleague's `terraform plan` is running when you start yours:

```text
…
Lock Info:
  ID:        15e018f5-3a48-cef5-36ce-cc1545f53b4c
  Path:      allcs-tfstate-319330935/hello/terraform.tfstate
  Operation: OperationTypePlan
  Who:       cloudshell-user@ip-10-141-113-28.us-east-1.compute.internal
  Version:   1.16.6
  Created:   2026-10-21 03:53:01.42103474 +0000 UTC
…
Terraform acquires a state lock to protect the state from being written
by multiple users at the same time. …
```
Real output: [M11-L03](../terraform/m11-l03-state/) (the video's capture `s08-lock.txt`).

<details>
<summary>Hint</summary>

What is being protected, and where does that lock live?

</details>

<details>
<summary>Model answer</summary>

State maps the addresses in my code to the real resource IDs, with cached attributes, and every plan compares against it. In a team it lives in a remote backend, like S3 with versioning and encryption, one state per environment and component, and it's locked during every operation so two applies can't corrupt it. That's what happened here: my plan refused to run while another plan held the lock on that state file, and the lock info says who and since when. Since Terraform 1.11 the S3 backend locks natively (`use_lockfile = true`), so a DynamoDB table isn't needed any more, and DynamoDB locking is deprecated. I never commit or hand-edit state; I change it only with `moved`, `import` and the `terraform state` commands. `force-unlock` only after confirming the other run is really dead.

</details>

### 41 · What is drift, and how do you handle it?
**Debug · Medium** · Covered in: [M11-L06 - Drift, Import and the Ecosystem](../terraform/m11-l06-drift-import-and-the-ecosystem/)

Nobody changed the code, yet the scheduled plan shows:

```text
asha@cloudshell:~$ terraform plan -no-color | grep -vE "^$" | tail -20
  # aws_s3_bucket.media will be updated in-place
  ~ resource "aws_s3_bucket" "media" {
        id                          = "allcs-media-dev-506c01"
      ~ tags                        = {
            "Name"  = "media-dev"
          ~ "Owner" = "priya-clickops" -> "asha"
        }
…
Plan: 0 to add, 1 to change, 0 to destroy.
```
Real output: [M11-L06](../terraform/m11-l06-drift-import-and-the-ecosystem/) (the video's capture `c02-plan.txt`).

<details>
<summary>Hint</summary>

Which side changed: the code, or the bucket?

</details>

<details>
<summary>Model answer</summary>

That's drift: real infrastructure no longer matches the code, here because someone changed the `Owner` tag in the console ("priya-clickops"), and Terraform wants to set it back to what the code says. A scheduled `terraform plan -detailed-exitcode` finds it (exit code 2 means changes). For each drift I decide: revert it with an apply, because the code is right, or adopt it by changing the code in a pull request, because the manual change was right. And I prevent it: read-only console access for people, changes through pull requests, and a break-glass role for emergencies that's logged and reviewed.

</details>

### 42 · Ansible or Terraform: when do you use which? And what does idempotent mean?
**Design · Medium** · Covered in: [M12-L01 - Ansible Basics](../ansible/m12-l01-ansible-basics/), [M12-L03 - Mutable vs Immutable Infrastructure](../ansible/m12-l03-mutable-vs-immutable-infrastructure/)

<details>
<summary>Hint</summary>

Provision versus configure. And what a second run should change.

</details>

<details>
<summary>Model answer</summary>

Terraform provisions infrastructure, declaratively, with state: networks, instances, databases, DNS. Ansible configures what runs on servers, over SSH, without agents: packages, files, services. Both should be idempotent: a second run against a server already in the desired state changes nothing, which I prove by running twice and checking that the second recap shows `changed=0` (guard `command` and `shell` tasks with `creates` or `changed_when`). For stateless app servers I'd rather bake an image (Packer plus Ansible) and replace instances, which is immutable; Ansible stays for stateful or legacy servers and for building those images.

</details>

### 43 · (new) How do you test a Terraform module without a cloud account?
**Scenario · Medium** · Covered in: [M11-L02 - HCL Basics](../terraform/m11-l02-hcl-basics/), [M11-L04 - Modules](../terraform/m11-l04-modules/), [M11-L05 - Environments and Pipelines](../terraform/m11-l05-environments-and-pipelines/)

A staged mistake (the private-subnet offset changed from 10 to 1) caught by the module's tests:

```text
$ terraform test
tests/subnet_plan.tftest.hcl... in progress
  run "layout_is_deterministic"... fail

Error: Test assertion failed
…
    │ Diff:
    │ --- actual
    │ +++ expected
    │   [
    │ -   "10.1.1.0/24",
    │ -   "10.1.2.0/24"
    │ +   "10.1.10.0/24",
    │ +   "10.1.11.0/24"
    │   ]
…
Failure! 5 passed, 1 failed.
exit 1
```
Captured for this sheet: take-home task 5, `hashicorp/terraform:1.16.6`, run with `--network none`.

<details>
<summary>Hint</summary>

Four layers of checks, from cheapest to most expensive. Which ones need no provider at all?

</details>

<details>
<summary>Model answer</summary>

In layers, cheapest first. `terraform fmt -check` and `terraform validate` on every pull request. `validation` blocks on variables, so a bad input fails at plan time with a clear message (in the same task, `environment = "production"` failed with "environment must be one of dev, staging, prod."). `precondition`, `postcondition` and `check` blocks for rules about computed values. And `terraform test` with `.tftest.hcl` files: `command = plan` runs make assertions on outputs, and `expect_failures` proves that bad inputs are rejected. A module whose logic is plain HCL (here `cidrsubnet()` and `terraform_data`) can be tested fully offline: the whole suite ran with no network at all. For modules that call a cloud provider, `mock_provider` blocks let plan-only tests run without credentials, and a real apply-and-destroy test runs nightly in a sandbox account. Here the test caught a real collision: offset 1 would have put a private subnet on top of a public one.

</details>

---

## Group G · Kubernetes

### 44 · What happens when you run `kubectl apply` on a Deployment?
**Concept · Medium** · Covered in: [M13-L01 - Why Orchestration](../k8s/m13-l01-why-orchestration/), [M13-L02 - Your First Cluster](../k8s/m13-l02-your-first-cluster/)

<details>
<summary>Hint</summary>

API server, etcd, three kinds of controllers, a scheduler and a kubelet.

</details>

<details>
<summary>Model answer</summary>

kubectl reads the current context from the kubeconfig and sends the object to that cluster's API server, which authenticates me, checks RBAC, runs admission (defaults, policies) and stores the desired state in etcd. The Deployment controller creates or updates a ReplicaSet, the ReplicaSet controller creates pods, the scheduler binds each pod to a node with room for its requests, and that node's kubelet asks containerd to pull the image and start the containers, then reports status back. And it keeps reconciling: delete a pod and the ReplicaSet makes a new one; change something by hand and the next apply puts it back.

</details>

### 45 · What happens during a rolling update, and how do you make it safe?
**Debug · Medium** · Covered in: [M13-L04 - Deployments and ReplicaSets](../k8s/m13-l04-deployments-and-replicasets/), [M14-L03 - Health and Resources](../k8s/m14-l03-health-and-resources/)

Two rollouts of the same app under the same traffic, the first without a readiness probe:

```text
asha@lab:~/allcsvideos$ kubectl exec deploy/traffic -- python traffic.py http://web 32 /tmp/g02-noprobe
…
06:38:52 1.0.0=15 err=5 pods=4
06:38:53 1.0.0=9 err=11 pods=2
06:38:54 1.0.0=6 err=14 pods=2
…
done: 640 requests, 94 failed
```
Real output: [M13-L04](../k8s/m13-l04-deployments-and-replicasets/) (the video's capture `g02-noprobe-traffic.txt`). With a readiness probe, the next run (`g04-probe-traffic.txt`) sent 900 requests and 0 failed.

<details>
<summary>Hint</summary>

When does a new pod count as available, and when does it start getting traffic?

</details>

<details>
<summary>Model answer</summary>

Changing the pod template creates a new ReplicaSet, which the Deployment controller scales up while it scales the old one down, within `maxSurge` and `maxUnavailable`, counting only pods that are Ready. Without a readiness probe, a pod is Ready as soon as its container starts, before the app listens, so the old pods were removed while the new ones still refused connections: 94 of 640 requests failed. With a readiness probe, 0 of 900. To make it safe: a readiness probe on a real endpoint, `maxUnavailable: 0` with a surge, a preStop delay so endpoints are removed before the process stops, a progress deadline, a change-cause, and `kubectl rollout undo` (which, remember, doesn't undo a ConfigMap or a schema).

</details>

### 46 · A pod calls another service by name. How does that request reach a pod?
**Concept · Medium** · Covered in: [M13-L05 - Services and DNS](../k8s/m13-l05-services-and-dns/)

<details>
<summary>Hint</summary>

Name to cluster IP, then cluster IP to one pod.

</details>

<details>
<summary>Model answer</summary>

The pod's `/etc/resolv.conf` points at CoreDNS, with search domains like `allcs.svc.cluster.local`, so `catalog` resolves to the Service's stable cluster IP. That IP isn't on any interface: kube-proxy's iptables or nftables rules on the node rewrite (DNAT) the connection to one ready pod from the Service's EndpointSlice, chosen per connection, and conntrack keeps that choice for the life of the connection. That's why a Service whose selector matches no pods has an empty EndpointSlice and refuses connections ([M20-B03](../capstones/m20-b03-troubleshooting-labs/) scenario 7).

</details>

### 47 · Liveness versus readiness probes, and how do requests and limits affect a pod?
**Debug · Medium** · Covered in: [M14-L03 - Health and Resources](../k8s/m14-l03-health-and-resources/), [M14-L06 - Troubleshooting Kubernetes](../k8s/m14-l06-troubleshooting-kubernetes/)

```text
asha@lab:~/allcsvideos$ kubectl logs thumbnailer-6fb7d7b875-p8qfj --previous | tail -3
thumbnail cache: 54 MiB
thumbnail cache: 56 MiB
thumbnail cache: 58 MiB
asha@lab:~/allcsvideos$ kubectl get pod thumbnailer-6fb7d7b875-p8qfj
NAME                           READY   STATUS    RESTARTS         AGE
thumbnailer-6fb7d7b875-p8qfj   1/1     Running   11 (5m42s ago)   45m
asha@lab:~/allcsvideos$ kubectl describe pod thumbnailer-6fb7d7b875-p8qfj | grep -A5 'Last State'
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
…
```
Real output: [M14-L06](../k8s/m14-l06-troubleshooting-kubernetes/) (the video's capture `f05-oom.txt`).

<details>
<summary>Hint</summary>

The pod says Running and Ready. Why is that not good news?

</details>

<details>
<summary>Model answer</summary>

Readiness decides whether a pod gets traffic: while it fails, the pod is removed from the Service's endpoints. Liveness restarts a stuck container, so it must check only the process itself, never a database or another service, or one slow dependency restarts every pod. A startup probe protects slow starters. Probe defaults in 1.37: every 10 s, a 1 s timeout, 3 failures. Requests are what the scheduler reserves on a node; limits are enforced by cgroups: over its CPU limit a container is throttled, over its memory limit it's OOMKilled with exit code 137. Together they set the QoS class that decides eviction order.

This pod looks fine right now (Running, 1/1), but it has restarted 11 times: each time its cache grows past the memory limit, the kernel kills it, and `Last State` shows OOMKilled, 137. Fix: set the limit from the measured peak plus headroom (or bound the cache), and alert on restarts and OOM kills, not just on "pod not running".

**Follow-up:** why does the HPA need requests? CPU utilization is a percentage of the request; without a request there is nothing to divide by.

</details>

### 48 · (updated) The API pods keep restarting after a release. Walk me through it.
**Scenario · Hard** · Covered in: [M14-L06 - Troubleshooting Kubernetes](../k8s/m14-l06-troubleshooting-kubernetes/), [M21-L01 - How DevOps Interviews Work](../interview/m21-l01-how-devops-interviews-work/), [M21-L03 - The Scenario Round](../interview/m21-l03-the-scenario-round/)

```text
asha@lab:~/allcsvideos$ kubectl logs api-7c6cc66b89-x9z2h --previous
unable to retrieve container logs for containerd://3c38396e9c58d27439a1954383b519021b66dfbb005de9b3287f2609e78963aaasha@lab:~/allcsvideos$ kubectl logs api-7c6cc66b89-x9z2h
FATAL: DATABASE_URL is not set. Refusing to start.
```
Real output: [M14-L06](../k8s/m14-l06-troubleshooting-kubernetes/) (the video's capture `d03-logs.txt`). Release 2.5.0 shipped a new image and a changed ConfigMap; the old image 2.4.0 crashes too.

<details>
<summary>Hint</summary>

Exit code 1, both versions crash, and one line of log. What do the old and new versions share? And what does `rollout undo` roll back?

</details>

<details>
<summary>Model answer</summary>

Clarify and set impact first: which pods, since when, what changed (here: release 2.5.0 at 13:06, a new image and a ConfigMap change), and the storefront answers 502, so it's high severity. Observe: `kubectl get pods` for restarts, `describe` for the last state (exit code 1, not 137, so the app gave up by itself, not memory) and the events, then the logs. `--previous` can fail when the container is already gone, so read the current logs too: one line, `DATABASE_URL is not set`. Because the old 2.4.0 image crashes as well, the new code isn't the cause; something both versions share changed: the config. `kubectl diff` against the last good file in git shows the release renamed the key to `DB_URL`.

Mitigate: `kubectl rollout undo` rolls back only the pod template; the ConfigMap is a separate object, so apply the last good ConfigMap from git, then `kubectl rollout restart`, because environment variables are read only at start. Verify from the user's side: pods Ready with zero restarts past the backoff window, the storefront answers. Prevent: an alert on the storefront's error rate, a runbook that says "read before you delete" (deleting the healthy pods made it worse), and config that rolls back with the release, like Kustomize's hashed ConfigMap names.

</details>

### 49 · Is a Kubernetes Secret secure?
**Concept · Medium** · Covered in: [M13-L06 - ConfigMaps and Secrets](../k8s/m13-l06-configmaps-and-secrets/), [M18-L02 - Secrets Management](../security/m18-l02-secrets-management/), [Module 13 practice sheet](m13-kubernetes.md)

<details>
<summary>Hint</summary>

Encoding is not encryption. And where does the API server store it?

</details>

<details>
<summary>Model answer</summary>

Not by default. A Secret is only base64-encoded, which anyone reverses without a key, and the API server stores it in etcd as plain bytes unless encryption at rest is configured; every etcd backup has it too. And `kubectl apply` keeps a copy of the whole manifest, `stringData` included, in the `last-applied-configuration` annotation (`--server-side` doesn't write it). So: enable encryption at rest with a KMS provider, restrict `get`, `list` and `watch` on Secrets with RBAC, and also who can create pods in the namespace (a pod can mount any Secret there), mount secrets as files, and keep the real values in a manager like Vault or AWS Secrets Manager, synced in by External Secrets Operator, so no plain secret lands in git.

</details>

### 50 · What is GitOps, and how is it different from `kubectl apply` in a pipeline?
**Design · Medium** · Covered in: [M15-L03 - GitOps with Argo CD](../k8s/m15-l03-gitops-with-argo-cd/), [M15-L01 - Helm](../k8s/m15-l01-helm/), [M15-L02 - Kustomize](../k8s/m15-l02-kustomize/)

<details>
<summary>Hint</summary>

Push versus pull, and who holds the cluster credentials.

</details>

<details>
<summary>Model answer</summary>

GitOps keeps the declarative desired state in git, and an agent inside the cluster, like Argo CD or Flux, pulls and reconciles it continuously. So the pipeline needs no cluster credentials, drift is detected and healed, every change is a reviewed commit, and rollback is `git revert`. A pipeline running `kubectl apply` pushes: CI holds a kubeconfig for production, and nothing notices or reverts a manual change made afterwards.

**Follow-up:** Helm or Kustomize? Helm: versioned charts with templates, to package, share and install third-party software. Kustomize: plain YAML with an overlay per environment, built into kubectl. Many teams use both: Helm charts rendered and patched per environment, applied by Argo CD.

</details>

### 51 · (new) `kubectl drain` hangs during node maintenance. Read the output.
**Debug · Medium** · Covered in: [M14-L04 - Autoscaling](../k8s/m14-l04-autoscaling/), [M14-L03 - Health and Resources](../k8s/m14-l03-health-and-resources/)

```text
$ kubectl drain m21lab-k8s-worker --ignore-daemonsets --delete-emptydir-data --timeout=40s
node/m21lab-k8s-worker cordoned
Warning: ignoring DaemonSet-managed Pods: kube-system/kindnet-lc8dq, kube-system/kube-proxy-nkjvk
evicting pod kube-system/metrics-server-84c99cb944-n5t6v
evicting pod allcs/cs-78d9b8dfc6-mfjps
…
error when evicting pods/"cs-78d9b8dfc6-mfjps" -n "allcs" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
…
pod/cs-78d9b8dfc6-hfd9h evicted
…
error: unable to drain node "m21lab-k8s-worker" due to error: [error when evicting pods/"cs-78d9b8dfc6-rskhn" -n "allcs": global timeout reached: 40s, …
$ kubectl -n allcs get pods -o wide
NAME                  READY   STATUS    RESTARTS   AGE     IP            NODE                  …
cs-78d9b8dfc6-5kcjb   0/1     Pending   0          41s     <none>        <none>                …
cs-78d9b8dfc6-5mptv   1/1     Running   0          4m34s   10.244.1.10   m21lab-k8s-worker     …
…
$ kubectl -n allcs get pdb cs
NAME   MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
cs     N/A             1                 0                     5m49s
```
Captured for this sheet: take-home task 6 (a kind cluster with one control plane and one worker; 5 replicas, PDB `maxUnavailable: 1`).

<details>
<summary>Hint</summary>

One pod was evicted. Where did its replacement go?

</details>

<details>
<summary>Model answer</summary>

The PodDisruptionBudget is doing its job. It allows one pod of `cs` to be unavailable at a time. Drain evicted one, and its replacement is Pending because the only other node is the control plane, which doesn't take workloads. Until the replacement is Ready, `ALLOWED DISRUPTIONS` is 0, so every further eviction is refused and drain retries until its timeout. Nothing is broken; the cluster simply has nowhere to put the pods. Fixes: add capacity first (a new node, or let the cluster autoscaler add one), then drain; spread replicas across nodes and zones with topology spread constraints, so a drain never needs all of them moved at once. What I wouldn't do: delete the PDB or use `--disable-eviction` to force it, because that's how a maintenance window becomes an outage. And a PDB with `maxUnavailable: 0` would block drains forever: that's a finding in a review.

</details>

### 52 · (new) A rollout is stuck and the new pod shows `ImagePullBackOff`. What do you check?
**Debug · Easy** · Covered in: [M13-L03 - Pods](../k8s/m13-l03-pods/), [M14-L06 - Troubleshooting Kubernetes](../k8s/m14-l06-troubleshooting-kubernetes/), [M20-B03 - Troubleshooting Labs](../capstones/m20-b03-troubleshooting-labs/)

```text
asha@ops:~$ kubectl get pods -l app=catalog
NAME                       READY   STATUS         RESTARTS   AGE
catalog-6cbd6b6df7-f8tvg   1/1     Running        0          2m25s
catalog-6cbd6b6df7-zlccg   1/1     Running        0          2m25s
catalog-ff9f4bd5b-h66dc    0/1     ErrImagePull   0          40s
asha@ops:~$ P=$(kubectl get pods -l app=catalog --sort-by=.metadata.creationTimestamp -o name | tail -1); kubectl events --for $P --types=Warning | tail -4
LAST SEEN           TYPE      REASON   OBJECT                        MESSAGE
25s (x2 over 39s)   Warning   Failed   Pod/catalog-ff9f4bd5b-h66dc   Failed to pull image "m21lab-tl-api:1.0.1": failed to pull and unpack image "docker.io/library/m21lab-tl-api:1.0.1": failed to resolve reference "docker.io/library/m21lab-tl-api:1.0.1": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
…
```
Captured for this sheet: take-home task 8, scenario 8 of the [M20-B03](../capstones/m20-b03-troubleshooting-labs/) troubleshooting labs (a staged fault).

<details>
<summary>Hint</summary>

Who is still serving users? And read the image name the node tried to pull, in full.

</details>

<details>
<summary>Model answer</summary>

Users are fine for now: the rolling update keeps the two old pods, because the new one never became Ready. The event says exactly what failed: the node tried to pull `docker.io/library/m21lab-tl-api:1.0.1`. A name without a registry defaults to Docker Hub, and "repository does not exist or may require authorization" means either the tag was never pushed, the registry or name is wrong, or the pull secret is missing. Here only `1.0` existed on the node: 1.0.1 was never built. Mitigate with `kubectl rollout undo` (or set the image to a tag that exists). Prevent: deploy only what CI pushed, referenced by digest from the build output, and gate the pipeline on `kubectl rollout status` so a stuck rollout fails the deploy instead of waiting for someone to notice.

</details>

### 53 · (new) Ingress or the Gateway API for a new cluster? And what does cert-manager do?
**Design · Medium** · Covered in: [M14-L01 - Ingress and the Gateway API](../k8s/m14-l01-ingress-and-the-gateway-api/)

<details>
<summary>Hint</summary>

One object versus a split by role. And check what happened to the most common Ingress controller.

</details>

<details>
<summary>Model answer</summary>

Ingress is a stable, frozen API where one object holds hosts, paths and TLS, and everything else (rewrites, timeouts, canary weights) lives in controller-specific annotations, so configs don't move between controllers. The Gateway API splits that into a GatewayClass (the implementation), a Gateway (listeners and TLS, owned by the platform team) and routes like HTTPRoute (owned by app teams), with typed, conformance-tested features: header matches, rewrites, traffic weights. For new work I'd choose the Gateway API. There's also a practical reason: ingress-nginx, the controller most tutorials use, was retired (announced November 2025, archived March 2026), so new clusters shouldn't start on it; the course used Traefik and NGINX Gateway Fabric. cert-manager watches Certificate objects (or annotated Gateways and Ingresses), gets certificates signed by an issuer such as Let's Encrypt over ACME or a private CA, stores them in Secrets that the controller serves, and renews them before they expire, which removes question 15's expired-certificate outage. Check its supported Kubernetes versions: in the course, cert-manager 1.21 needed a 1.36 node image.

</details>

---

## Group H · Observability, SRE and incidents

### 54 · What is the difference between DevOps and SRE, and where does platform engineering fit?
**Concept · Easy** · Covered in: [M01-L02 - DevOps, SRE and Platform Engineering](../setup/m01-l02-devops-sre-and-platform-engineering/)

<details>
<summary>Hint</summary>

A culture, a practice, a product.

</details>

<details>
<summary>Model answer</summary>

DevOps is a culture of shared ownership between development and operations: small changes, automation, fast feedback, and "you build it, you run it". SRE is one concrete way to practise it, from Google: reliability as a number (SLOs and error budgets), a cap on toil, and engineers who automate operations away. Platform engineering packages those practices into a self-service internal product, golden paths that make the right way the easy way. In job listings the titles overlap, so read the tool list, not the title.

</details>

### 55 · You're launching a new service. What do you measure?
**Design · Medium** · Covered in: [M16-L01 - The Three Pillars and What to Measure](../observability/m16-l01-the-three-pillars-and-what-to-measure/), [M16-B01 - Full Observability for allcsvideos](../observability/m16-b01-full-observability-for-allcsvideos/)

<details>
<summary>Hint</summary>

The user's view first, then the resources underneath, then the context to debug.

</details>

<details>
<summary>Model answer</summary>

From the user's side, the golden signals: request rate, errors, latency percentiles from histograms (not averages), and saturation of whatever runs out first (connections, queue length, CPU). Underneath, for each resource, utilization, saturation and errors (USE). Plus structured logs with a request or trace ID, and distributed traces across services, with exemplars so a slow point on a graph links to its trace. And I alert on symptoms, not on CPU: in [M16-L01](../observability/m16-l01-the-three-pillars-and-what-to-measure/) a database lock wait dropped the database's CPU from 17.1% to 1.6% while 96.5% of requests failed, so a CPU alert would have stayed silent.

</details>

### 56 · How does Prometheus collect metrics, and how do you get the error rate and p95 latency?
**Concept · Medium** · Covered in: [M16-L02 - Metrics with Prometheus](../observability/m16-l02-metrics-with-prometheus/)

<details>
<summary>Hint</summary>

Pull. Then two PromQL patterns.

</details>

<details>
<summary>Model answer</summary>

Prometheus pulls: it scrapes each target's `/metrics` endpoint on an interval and stores every series under a metric name and its labels. Error ratio:

```promql
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
```

p95 latency from a histogram:

```promql
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
```

And keep label values bounded: a label with user IDs or full URLs creates a series per value and takes Prometheus down (in [M17-L03](../observability/m17-l03-load-testing-and-capacity-planning/) k6's per-URL tags did exactly that until a `name` tag replaced them).

</details>

### 57 · How do you design alerting that people trust?
**Design · Medium** · Covered in: [M16-L06 - Alerting](../observability/m16-l06-alerting/)

<details>
<summary>Hint</summary>

What pages, what doesn't, and how Alertmanager keeps the noise down.

</details>

<details>
<summary>Model answer</summary>

Page only on symptoms users feel, like the error ratio and p99 latency, each with a `for:` duration and a runbook link. Causes (CPU, disk at 70%, one pod restarting) go to dashboards and tickets. Alertmanager groups alerts by service so an outage is one page, routes by severity and team, inhibits the symptom alerts when a "whole site down" alert fires, and silences planned work. Rules are unit-tested with `promtool test rules` in CI, and every page is reviewed weekly: was it real, was it actionable, did the runbook help? An alert nobody acts on gets fixed or deleted.

</details>

### 58 · What are SLIs, SLOs and error budgets, and how do you alert on them?
**Concept · Hard** · Covered in: [M17-L01 - SLIs, SLOs and Error Budgets](../observability/m17-l01-slis-slos-and-error-budgets/)

<details>
<summary>Hint</summary>

A ratio, a target, the rest. Then two windows per alert.

</details>

<details>
<summary>Model answer</summary>

An SLI is good events over valid events, measured as close to the user as possible, for example the share of course-list requests that don't return 5xx. The SLO is its target over a rolling window, like 99.9% over 30 days, and the error budget is the rest: 0.1% of requests may fail, about 43 minutes of full outage in 30 days. I alert on burn rate, how fast the budget is spent, with two windows per alert: 14.4 times over 1 hour, confirmed over 5 minutes, pages (2% of the budget in an hour); 6 times over 6 hours with 30 minutes also pages; 3 times over 1 day and 1 time over 3 days open tickets. The long window says it's significant, the short window says it's still happening, so the page ends soon after recovery. Agree a budget policy with product: when the budget is spent, only reliability work ships.

</details>

### 59 · (new) You fixed the bug, and the 1-hour burn page cleared. Twenty minutes later a page is still open. Is the alerting broken?
**Debug · Hard** · Covered in: [M17-L01 - SLIs, SLOs and Error Budgets](../observability/m17-l01-slis-slos-and-error-budgets/), [M16-L06 - Alerting](../observability/m16-l06-alerting/)

A live run with 20% errors, then the fix at 22:43:32 UTC:

```text
22:44:10 firing/CatalogErrorBudgetBurn1h firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn
…
22:47:49 firing/CatalogErrorBudgetBurn1h firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn
22:48:20 firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn
```
Captured for this sheet: take-home task 7, `prom/prometheus:v3.15.0`. The same behaviour as a unit test:

```yaml
      # 10 minutes after recovery the 5m window is clean, so the 1h page has ended ...
      - {eval_time: 100m, alertname: CatalogErrorBudgetBurn1h, exp_alerts: []}
      # ... but the 30m short window still holds errors, so the 6h page is still firing
      - eval_time: 100m
        alertname: CatalogErrorBudgetBurn6h
…
      - {eval_time: 125m, alertname: CatalogErrorBudgetBurn6h, exp_alerts: []}
```
`promtool test rules slo-tests.yml` printed `SUCCESS` (task 7).

<details>
<summary>Hint</summary>

Each alert has a long and a short window. Which short window is 5 minutes, and which is 30?

</details>

<details>
<summary>Model answer</summary>

No, it's the design. The 14.4x alert pairs the 1-hour window with a 5-minute window, so about 5 minutes after the fix the short window is clean and that page resolves (here between 22:47:49 and 22:48:20, under 5 minutes after the fix). The 6x alert pairs the 6-hour window with a 30-minute window, so it keeps firing until 30 minutes after the errors stopped, even though the service is healthy. Options: accept it, and say in the runbook that the 6h page lags recovery; let Alertmanager's grouping and the incident process close it; or, since it means the same outage, inhibit the 6h page while the 1h page fires. What I'd not do is drop the short windows: without them both pages would stay open for an hour or more after every incident. The unit test encodes the behaviour, so nobody "fixes" it by accident.

**Follow-up:** why is there also a `CatalogScrapeMissing` alert? A dead target has no errors at all: the error ratio has no data, so the SLO alerts can't fire. In [M17-L01](../observability/m17-l01-slis-slos-and-error-budgets/), stopping the API gave a server-side error ratio of 0 while clients saw 40% failures.

</details>

### 60 · What roles does an incident need, and what makes a postmortem blameless?
**Concept · Medium** · Covered in: [M17-L02 - Incident Response](../observability/m17-l02-incident-response/)

<details>
<summary>Hint</summary>

Three roles, one rule for the first hour, one question for the postmortem.

</details>

<details>
<summary>Model answer</summary>

An incident commander who coordinates and decides, and doesn't debug; someone who leads operations and works the fix; and a comms lead who updates the status page and stakeholders. In the first hour: mitigate first (roll back, fail over, switch off the feature), and keep a timestamped timeline as you go. A blameless postmortem asks how the system let this happen, not who did it: people acted reasonably on what they knew, so the fix is in the system (a guardrail, an alert, a runbook, a test). Every action item gets an owner and a date, and the review is shared so other teams learn from it.

</details>

### 61 · What are RTO and RPO, and how do you know you can recover?
**Concept · Medium** · Covered in: [M17-L04 - Chaos Engineering and Disaster Recovery](../observability/m17-l04-chaos-engineering-and-disaster-recovery/)

<details>
<summary>Hint</summary>

One counts forward from the disaster, one counts backward.

</details>

<details>
<summary>Model answer</summary>

RTO, the recovery time objective, is how long recovery may take, counted forward from the disaster until users are served again. RPO, the recovery point objective, is how much data you may lose, counted backward from the disaster to the last good copy. The business agrees both before anything breaks. I keep backups off-site with continuous WAL archiving, and restore them on a schedule, timing the RTO and measuring the RPO from real timestamps. [M17-L04](../observability/m17-l04-chaos-engineering-and-disaster-recovery/)'s restore drill measured an RTO of 46 seconds and an RPO of 62 seconds, with 125 confirmed enrollments lost. A backup you've never restored isn't a backup.

</details>

### 62 · (new) Your first disaster-recovery drill missed both targets. What do you change?
**Scenario · Hard** · Covered in: [M20-B02 - Disaster-Recovery Drill](../capstones/m20-b02-disaster-recovery-drill/)

```text
asha@ops:~/drill1$ dr/report.py 'drill 1'
== drill 1
disaster (staged)              03:04:24
  +   0 min 06 s  step 1 infrastructure
  +   0 min 21 s  step 2 vault
  +  10 min 01 s  step 2 hung
…
newest confirmed row restored  02:56:50
RPO (data lost)                7 min 34 s, 908 confirmed enrollments gone
students enroll again          03:29:01  RTO 24 min 36 s
verify passed, clock stopped   03:29:05  RTO 24 min 40 s
```
Real output: [M20-B02](../capstones/m20-b02-disaster-recovery-drill/) (the video's capture `g11_report.txt`). Targets, agreed before the drill: RTO 15 minutes, RPO 5 minutes. PostgreSQL had `archive_timeout = 0`, the default.

<details>
<summary>Hint</summary>

Treat the two misses separately. What does `archive_timeout = 0` mean for when a WAL file leaves the server?

</details>

<details>
<summary>Model answer</summary>

First, the drill worked: it found the gaps in a rehearsal, not in a real disaster, so the report is blameless and goes into git next to the runbook. Then each miss on its own. The RPO: with `archive_timeout = 0`, a WAL segment only leaves the server when 16 MB fill up or a base backup runs, which at this traffic took hours, so the newest restorable row was the base backup. Set `archive_timeout` (60 s in the build), alert when the newest archived WAL is older than the RPO target, and make the scheduled restore test fail when the restored data is older than the target (it then failed on the old backups, as it should). The RTO: the timeline shows where the minutes went, a step that hung silently for 10 minutes and a manual fix later on. Add timeouts and loud failures to every step, fix the dependency that trusted a dead cluster, and parallelise independent steps. Then run the drill again: the second run measured RTO 6 min 22 s and RPO 22 s, 44 enrollments lost, inside both targets. Not zero: the last WAL file was still on the dead server, and getting closer to zero needs a streaming replica, not better backups.

</details>

### 63 · (new) The API answers 503 in 20 milliseconds, and its journal says "remaining connection slots are reserved". What now?
**Debug · Medium** · Covered in: [M20-B03 - Troubleshooting Labs](../capstones/m20-b03-troubleshooting-labs/), [M10-L05 - Storage and Databases](../cloud/m10-l05-storage-and-databases/)

```text
asha@web-01:~$ sudo journalctl -u allcs-api -n 1 --no-pager -o cat
database error: connection to server at "db-01.allcsvideos.test" (10.0.205.20), port 5432 failed: FATAL:  remaining connection slots are reserved for roles with the SUPERUSER attribute
asha@ops:~$ psql -h db-01.allcsvideos.test -U postgres -d allcs -c "SELECT usename, application_name, state, count(*) FROM pg_stat_activity WHERE backend_type = 'client backend' GROUP BY 1, 2, 3 ORDER BY 4 DESC"
  usename  | application_name | state  | count 
-----------+------------------+--------+-------
 allcs_app | nightly-report   | idle   |    17
 postgres  | psql             | active |     1
(2 rows)

asha@ops:~$ psql -h db-01.allcsvideos.test -U postgres -d allcs -tAc "SHOW max_connections"
20
```
Captured for this sheet: take-home task 8, scenario 9 of the [M20-B03](../capstones/m20-b03-troubleshooting-labs/) troubleshooting labs (a staged fault).

<details>
<summary>Hint</summary>

Fast failures point away from the network. Who holds the connections, and in which state?

</details>

<details>
<summary>Model answer</summary>

A 503 in 20 ms means the database answered at once and refused, not that it was slow or unreachable. PostgreSQL allows 20 connections and keeps a few reserved for superusers, which is why my `psql` as postgres still gets in. `pg_stat_activity` shows who uses them: the nightly report holds 17 connections, all idle, so it leaks connections instead of closing them. Mitigate: stop the job (its connections close; the count dropped to 1 and the API answered 200), or `pg_terminate_backend()` on its sessions. Fix and prevent: fix the job to use one connection or a pool and close it; put PgBouncer in front of the database; give batch roles their own `CONNECTION LIMIT`; set `idle_session_timeout` or `idle_in_transaction_session_timeout`; and alert when connections pass 80% of `max_connections`, before users see errors.

</details>

---

## Group I · Security

### 64 · What does shift left mean, and where does security go in a pipeline?
**Concept · Medium** · Covered in: [M18-L01 - Shift Left](../security/m18-l01-shift-left/), [M18-B01 - A Secure Delivery Pipeline](../security/m18-b01-a-secure-delivery-pipeline/)

<details>
<summary>Hint</summary>

Stage by stage, from design to runtime. And when should a gate block?

</details>

<details>
<summary>Model answer</summary>

Shift left means finding problems at the earliest, cheapest stage: a threat model at design time; secret scanning in pre-commit hooks and in CI; SAST and dependency scans at build; image scans and an SBOM at package time; IaC scans and admission policies at deploy; DAST against staging; and monitoring at run time. Gates block only on high-confidence, fixable findings (for example HIGH or CRITICAL with a fix available), and exceptions are written down with an owner and an expiry date, so the gate stays trusted instead of being bypassed. And a scanner that reports 0 findings hasn't proved the code safe: in [M18-L01](../security/m18-l01-shift-left/) a registry rule pack missed a SQL injection that a local rule caught.

</details>

### 65 · A developer pushed an AWS key to a public repository. What do you do?
**Scenario · Medium** · Covered in: [M18-L02 - Secrets Management](../security/m18-l02-secrets-management/), [M18-L01 - Shift Left](../security/m18-l01-shift-left/)

<details>
<summary>Hint</summary>

The order matters. What is the first minute for?

</details>

<details>
<summary>Model answer</summary>

Revoke or rotate the key first, because it's compromised the moment it's public (bots scan public pushes within minutes), and check CloudTrail for everything it did. Then clean the history with `git filter-repo`, force-push, have the server, forks and clones cleaned, and everyone re-clone; deleting the file in a new commit leaves it in history. Then prevent a repeat: short-lived credentials from a secrets manager or OIDC, a gitleaks pre-commit hook, the same scan as a required CI gate (a commit that skips the hook still gets caught), and push protection on the forge.

**Follow-up:** take-home task 9 does this offline: `gitleaks git` finds a fake key in commit 2 even though commit 3 removed it, and after `git filter-repo --sensitive-data-removal --replace-text` the same scan prints "no leaks found".

</details>

### 66 · How should a CI pipeline get access to the cloud?
**Design · Medium** · Covered in: [M08-L05 - Secrets and OIDC](../ci/m08-l05-secrets-and-oidc/), [M11-L05 - Environments and Pipelines](../terraform/m11-l05-environments-and-pipelines/)

<details>
<summary>Hint</summary>

No long-lived keys. What does the job prove about itself instead?

</details>

<details>
<summary>Model answer</summary>

No long-lived keys stored as CI secrets. The job requests a short-lived OIDC token from the CI platform, signed by its issuer, and the cloud role trusts that issuer only for one audience (`sts.amazonaws.com`) and a subject pinned to one repository and branch, or a protected environment. AWS exchanges it for temporary credentials that expire with the job. Plans use a read-only role; applies to production use a separate role reachable only from the protected environment. Check what your platform supports: in the course, Gitea 28.1.0 doesn't issue OIDC tokens to jobs, so the lab used a labelled stand-in issuer with Vault.

</details>

### 67 · How would you secure the software supply chain of a container image?
**Design · Hard** · Covered in: [M18-L03 - Supply-Chain Security](../security/m18-l03-supply-chain-security/), [M18-B01 - A Secure Delivery Pipeline](../security/m18-b01-a-secure-delivery-pipeline/), [M07-L03 - Image Security](../docker/m07-l03-image-security/)

<details>
<summary>Hint</summary>

From the dependencies you pull in, to what the cluster agrees to run.

</details>

<details>
<summary>Model answer</summary>

Lock every dependency, transitive ones included, with versions and hashes; pin base images and CI tools by digest (the course pins Trivy by digest because of the March 2026 compromise of some of its release tags). Scan the lock file and the image in CI, and generate an SBOM for every release. Sign the image digest with cosign, keyless through OIDC where possible, and attach the SBOM and the build provenance as signed attestations; aim for SLSA build level 2 or 3. Verify signatures before anything is deployed, in CI and at admission, and rescan the stored SBOMs on a schedule, because new CVEs appear for old images.

</details>

### 68 · (new) Someone pushed a different image over the tag `1.0.0`. What stops it from reaching production?
**Debug · Hard** · Covered in: [M18-L03 - Supply-Chain Security](../security/m18-l03-supply-chain-security/), [M18-L04 - Kubernetes Security](../security/m18-l04-kubernetes-security/), [M18-B01 - A Secure Delivery Pipeline](../security/m18-b01-a-secure-delivery-pipeline/)

```text
# staged: someone pushes a different image over the same tag
$ docker tag m21lab-t02-app:starter localhost:21055/allcs/course-search:1.0.0 && docker push -q localhost:21055/allcs/course-search:1.0.0
localhost:21055/allcs/course-search:1.0.0
$ cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry -o text localhost:21055/allcs/course-search:1.0.0
WARNING: Skipping tlog verification is an insecure practice that lacks transparency and auditability verification for the signature.
Error: no signatures found
error during command execution: no signatures found
exit 10
```
Captured for this sheet: take-home task 9, `ghcr.io/sigstore/cosign/cosign:v3.1.4`, an offline lab registry (`registry:3.1.2`).

<details>
<summary>Hint</summary>

What exactly did cosign sign: the tag or the digest? And what does the cluster accept?

</details>

<details>
<summary>Model answer</summary>

cosign signs a digest, not a tag. The tag `1.0.0` now points at a new digest that nobody signed, so verification fails ("no signatures found", exit code 10) and a pipeline gate that verifies before deploying stops it. The original, signed digest still verifies. So the defence has three parts: resolve the tag to a digest and verify that digest's signature in the deploy step; deploy by digest, never by tag, so a moved tag changes nothing that's already running; and enforce it in the cluster with an admission policy. In task 9 a native ValidatingAdmissionPolicy denies any image in the opted-in namespace that isn't from the team registry and pinned by `@sha256:` (`kubectl apply --dry-run=server` showed "images must be pinned by digest"), and signature checks at admission need a policy engine such as Kyverno or the Sigstore policy controller. Plus make tags immutable in the registry, if it supports it (the lab registry doesn't), and limit who can push.

**Trap:** `--insecure-ignore-tlog` is a lab setting for an offline registry, and cosign prints a warning for it. In production, keyless signing with a transparency log is the default.

</details>

### 69 · A pod in your cluster is compromised. What limits the damage?
**Design · Hard** · Covered in: [M18-L04 - Kubernetes Security](../security/m18-l04-kubernetes-security/), [M19-L02 - FinOps](../platform/m19-l02-finops/)

<details>
<summary>Hint</summary>

Layers: identity, network, the node, and what may run at all.

</details>

<details>
<summary>Model answer</summary>

Layers. Least-privilege RBAC, with `automountServiceAccountToken: false` unless the app calls the API, so a stolen pod has no useful token. Default-deny NetworkPolicies that allow only the paths it needs, including DNS, so it can't reach the database of another service or the cloud metadata endpoint. The restricted Pod Security Standard (non-root, no privilege escalation, all capabilities dropped, seccomp), so escaping to the node is much harder. Admission policies that only admit signed images pinned by digest from our registry. And detection: audit logs and runtime alerts. Choosing the admission tool is a trade-off: a native ValidatingAdmissionPolicy (CEL, GA since 1.30) needs nothing extra to run but can't verify signatures; Kyverno can, but it's one more controller with its own supported Kubernetes versions (in the course, Kyverno 1.19 needed a 1.35 node image).

</details>

---

## Group J · Platform, cost and AI

### 70 · What is an internal developer platform, and how do you know it is working?
**Design · Medium** · Covered in: [M19-L01 - Internal Developer Platforms](../platform/m19-l01-internal-developer-platforms/)

<details>
<summary>Hint</summary>

A product, with customers. What would its customers measure?

</details>

<details>
<summary>Model answer</summary>

An internal developer platform is a product, owned by a platform team, that gives other teams self-service golden paths over shared capabilities: create a service, get CI, environments, observability and secrets wired in. A portal like Backstage is its front door, not the platform itself. Start by interviewing the teams and fixing their worst wait, not by installing plugins. It's working when lead time for a new service drops, adoption grows without a mandate, DORA metrics and developer satisfaction improve, and tickets to the platform team go down. Keep the caveats of your evidence: in [M19-L01](../platform/m19-l01-internal-developer-platforms/) the template took a new service from form to green pipeline in about 9 seconds, but it covered 5 of the 8 old tickets, not all of them.

</details>

### 71 · Our cloud bill doubled. What do you do?
**Scenario · Medium** · Covered in: [M19-L02 - FinOps](../platform/m19-l02-finops/)

<details>
<summary>Hint</summary>

Visible and owned before cheaper.

</details>

<details>
<summary>Model answer</summary>

First make cost visible and owned: enforce tags like team and cost center (an admission policy can refuse untagged workloads), allocate cost per team and per unit of value, like cost per thousand video plays, and find out whether the growth is usage, which may be fine, or waste. Then rightsize from measured p95 usage, switch off idle and non-production resources outside working hours, look at data transfer and NAT gateway charges, and only then buy Savings Plans for the steady baseline and use Spot for stateless, interruptible work. Add budgets and anomaly alerts so the next jump isn't a surprise. And remember that rightsizing a Kubernetes workload is a rollout: in [M19-L02](../platform/m19-l02-finops/), changing requests without a preStop delay failed 28 of 5,203 requests.

</details>

### 72 · (new) How would you use an LLM in incident response, and how do you know it helps?
**Design · Hard** · Covered in: [M19-L04 - AI in DevOps](../platform/m19-l04-ai-in-devops/)

<details>
<summary>Hint</summary>

What does it get to see, what may it do, and how was it graded?

</details>

<details>
<summary>Model answer</summary>

Classic AIOps first: anomaly detection and alert correlation, which are cheaper and well understood. Then an LLM as an assistant, not an operator: give it a small, redacted bundle (the firing alerts, recent deploys, the top errors, one slow trace), ask for a root cause that cites the evidence and suggests read-only next steps, and verify every claim against the real telemetry. A human approves every change, its tools are read-only, and log lines are treated as data, because an instruction hidden in a log line can steer the model. And measure it on past incidents with known causes before trusting it: in [M19-L04](../platform/m19-l04-ai-in-devops/) a local 3-billion-parameter model ran on 15 of the course's own past incidents. The keyword rule, written before any run, scored it 10 of 15; a human review found only 7 of 15 truly right. So grade the grader, and report the human number.

</details>

---

## Group K · Behavioural

Use STAR: **situation, task, action, result**, then one line of what you learned. Say "I", be honest about your part, put a number in the result, and stay around two minutes. The course stories below are **practice examples from labs**: their faults were staged and some people were scripted. In a real interview, say that it was a lab or a game day, or use a story from your own work in the same shape.

### 73 · (new) Tell me about an incident you led.
**Behavioural · Medium** · Covered in: [M17-B01 - Game Day with SLOs, Chaos and a Postmortem](../observability/m17-b01-game-day-with-slos-chaos-and-a-postmortem/), [M21-L01 - How DevOps Interviews Work](../interview/m21-l01-how-devops-interviews-work/)

<details>
<summary>Hint</summary>

The game day: you were incident commander. Which number shows the result?

</details>

<details>
<summary>Model answer</summary>

A practice answer built from the Module 17 game day (a lab; say so):

- **Situation:** before a launch, the team ran a game day in staging, with faults the responders didn't know in advance.
- **Task:** I was incident commander. The goal was to prove that our SLOs, pages and runbooks held, while spending at most 10% of any error budget.
- **Action:** when Course Copilot hung and took the course list down with it, I approved the kill switch, and the failures stopped about a second later. In the blameless review we found why a slow dependency took down a healthy service: nginx treated slow answers as dead replicas, because `max_fails` counted timeouts.
- **Result:** release 1.2 added circuit breakers and bulkheads. On the re-run, zero course-list requests failed while Copilot was down, and the whole game day spent 7.70% of the budget, under the 10% cap.
- **Learned:** triage from the SLIs on the board, not from an alert's description.

**Follow-ups to expect:** what would you do differently as incident commander? Who wrote the timeline? What was the hardest decision, and what did it cost (the kill switch removed a feature for everyone)?

</details>

### 74 · (new) Tell me about a time a mistake made an incident worse.
**Behavioural · Medium** · Covered in: [M14-L06 - Troubleshooting Kubernetes](../k8s/m14-l06-troubleshooting-kubernetes/), [M21-L01 - How DevOps Interviews Work](../interview/m21-l01-how-devops-interviews-work/)

<details>
<summary>Hint</summary>

Rahul's 11 p.m. delete in [M14-L06](../k8s/m14-l06-troubleshooting-kubernetes/). Own it, then show what changed afterwards.

</details>

<details>
<summary>Model answer</summary>

A practice answer built from the [M14-L06](../k8s/m14-l06-troubleshooting-kubernetes/) lab, told from the point of view of the person who made the mistake (the lab staged the fault; the story is the course's):

- **Situation:** late in the evening, release 2.5.0 of the API went out (13:06 on the cluster clock) with a renamed config key, and its new pod crashed. The two old pods were still serving.
- **Task:** I was on call and joined to stabilise it.
- **Action:** I deleted the two old pods to "give them a fresh start", without reading the logs first. They came back, read the same renamed key at start, and crashed too: by 13:08:05 every API pod was failing, and the storefront answered 502. Then I stopped, read the logs (`DATABASE_URL is not set`), compared the ConfigMap with git, applied the last good one and restarted the rollout. Healthy pods by 13:15:47.
- **Result:** my delete turned a partial outage into a full one, for almost eight minutes (13:08:05 to 13:15:47). In the postmortem I wrote my delete as the first line of the timeline, and we added a runbook rule ("read before you delete"), an alert on the storefront's error rate, and config that rolls back with the release.
- **Learned:** a restart without a diagnosis is a guess, and guesses make outages longer.

**Why this works in an interview:** it shows ownership without self-punishment, a concrete number, and changes to the system rather than "I'll be more careful".

</details>

### 75 · (new) Tell me about a time you improved security without slowing the team down.
**Behavioural · Medium** · Covered in: [M18-L01 - Shift Left](../security/m18-l01-shift-left/), [M21-L01 - How DevOps Interviews Work](../interview/m21-l01-how-devops-interviews-work/)

<details>
<summary>Hint</summary>

The fake AWS key of [M18-L01](../security/m18-l01-shift-left/), found twelve days after the commit. What was the first action, and what proved the fix?

</details>

<details>
<summary>Model answer</summary>

A practice answer built from [M18-L01](../security/m18-l01-shift-left/) (a staged, fake key; say so):

- **Situation:** a secret scan found an AWS key in our repository, twelve days after it was committed, and it was already in a release.
- **Task:** contain it, then make sure the next one is caught on day one, without making every pull request slower.
- **Action:** I treated the key as compromised and revoked it first, before cleaning anything, and checked what it had been used for. Then I added a gitleaks pre-commit hook, which gives the developer the answer in under a second on their own machine, and the same scan as a CI gate, made a required check on main, so a commit that skips the hook is still caught.
- **Result:** a later commit that skipped the hook was blocked by the pipeline. In the lesson's words, the key would have cost one line to fix on day one; twelve days later it cost a project.
- **Learned:** put the cheap check where the developer is, and the mandatory check where nobody can skip it.

**Follow-ups to expect:** how did you handle false positives? (an allowlist with a reason and an owner, reviewed like code). How did you get the team to accept the hook? (fast, local, and the CI gate made it pointless to skip).

</details>

---

## Score yourself

Score each question honestly, **right after** you answer it out loud and **before** you read the model answer in full:

| Score | Meaning |
|---|---|
| **2** | You gave the core of the model answer in your own words, within the time limit, with the reasoning, and you'd survive the follow-up. For Debug questions: you named the cause from the output. For Behavioural: STAR, a number, and what you learned. |
| **1** | Right direction, but vague, slow, or missing the key point (the trap, the number, the order of steps). |
| **0** | Wrong, blank, or a list of tool names without a method. |

**Add it up (maximum 150):**
- **120 or more:** you're ready for the loop. Spend your time on the take-home tasks and on mock interviews with a friend.
- **90 to 119:** solid, with gaps. Rewatch the lessons named under every question you scored 0 or 1, re-run their labs, and redo those questions in a week.
- **Under 90:** go back group by group. Start with the groups where you lost the most points; they're usually the ones you've practised least with your hands.

These bands are a self-check for this sheet, not a hiring bar; every company scores against its own rubric.

**Look at where you lost points, not only how many:**
- Lost points on **Debug** questions? You're reading outputs too fast. Practise with the Module 2, 5 and 13 practice sheets and the [M20-B03](../capstones/m20-b03-troubleshooting-labs/) troubleshooting labs: say what each line tells you before you guess.
- Lost points on **Scenario** questions? Check that you clarified first, mitigated before root-causing, and said how you'd verify from the user's side. Those three are the most common gaps ([M21-L01](../interview/m21-l01-how-devops-interviews-work/)).
- Lost points on **Design** questions? Name the requirement that decides, two options, and the trade-off you accept. "It depends" is only the start of an answer.
- Lost points on **Behavioural** questions? Write your own three stories (an incident, a failure, an improvement) in STAR form, with one number each, and practise them until they take two minutes.

**Three habits that matter more than any score:**
1. **Say a number.** "94 of 640 requests failed without a readiness probe" beats "rolling updates can drop requests". You've measured dozens of numbers in this course; learn ten by heart.
2. **Say how you'd know.** Every fix ends with verification from the user's side, and every claim with the command that proves it.
3. **Say what you'd change so it can't happen the same way twice.** The alert, the runbook, the test, the guardrail.
