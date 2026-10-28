# M02-L06 · SSH and Remote Servers
> Video: Module 2, Lesson 6. Watch it first, then follow along here.

## What you'll learn
- What happens in the first second of an SSH connection: host keys, `known_hosts`, and checking a fingerprint before typing `yes`
- How to log in with a key instead of a password: `ssh-keygen`, `ssh-copy-id`, `authorized_keys`, and `ssh-agent`
- How to turn long commands into short names with `~/.ssh/config`, and reach private servers through a bastion with `ProxyJump`
- How to copy files with `scp` and deploy a folder with `rsync` (dry run first), and how to open a tunnel with `ssh -L`
- How to harden `sshd` (no root, no passwords, `AllowUsers`) without locking yourself out, and how to give a teammate access safely

## Before you start
- Docker Desktop (or Docker Engine) running on your laptop, and about 1.5 GB of free disk space for the lab images.
- You only need this folder. The servers run systemd inside containers, like the lab in M02-L03.
- The lab creates two Docker networks, `203.0.113.0/24` (a range reserved for documentation, standing in for public addresses) and `10.0.1.0/24`. If `10.0.1.0/24` is already used on your network, edit both subnets and IPs in `lab/up.sh` and in your SSH config.
- Every password and passphrase here is a **fake demo value** for this throwaway lab: asha `demo-password-123`, priya `demo-priya-pass`, database role `allcs` `demo-db-password`. Pick your own key passphrases (the video used `demo-passphrase-123`).

| Machine | Container | Address | Role |
|---|---|---|---|
| Asha's laptop | `laptop` | 203.0.113.50 | ssh client, you work here |
| Priya's laptop | `priya-laptop` | 203.0.113.51 | ssh client |
| bastion | `bastion` | 203.0.113.10 and 10.0.1.10 | the only door into the private network |
| web-01 | `web-01` | 10.0.1.11 | private web server |
| db-01 | `db-01` | 10.0.1.21 | private database server (PostgreSQL 16, localhost only) |

## Files in this folder
| File | What it is |
|---|---|
| `lab/image/Dockerfile` | Server image `ssh-lab-sshd:1`: Ubuntu 24.04, systemd, OpenSSH server and client, rsync, psql client |
| `lab/image-db/Dockerfile` | `ssh-lab-db:1`: the same plus PostgreSQL |
| `lab/setup-server.sh` | Gives each server its own host keys and creates users `asha` and `priya` |
| `lab/setup-db.sh` | Creates the `allcsvideos` database with a `courses` table on db-01 |
| `lab/setup-laptop.sh` | Creates the single user on a laptop container |
| `lab/site/` | Asha's storefront build: two pages, three assets and an old landing page (copied to `~/site` on her laptop) |
| `lab/up.sh` / `lab/down.sh` | Create / remove the networks, containers and images |
| `lab/send-priya-key.sh` | Copies Priya's **public** key to Asha's laptop as `~/priya.pub` (the "sent in chat" step) |
| `reference/asha-ssh-config` | Asha's final `~/.ssh/config`, to compare with yours |
| `reference/priya-ssh-config` | Priya's `~/.ssh/config` |
| `reference/10-hardening.conf` | The corrected hardening file (the video types it with two mistakes on purpose) |

## Follow along
Lines starting with `docker exec` run in a terminal on **your own computer**. Everything else runs inside the lab shell named in the step.

### 1. Start the lab and open Asha's laptop
```bash
./lab/up.sh
docker exec -it laptop su - asha
```

### 2. First connection and the host key
```bash
ssh asha@203.0.113.10
```
```
The authenticity of host '203.0.113.10 (203.0.113.10)' can't be established.
ED25519 key fingerprint is SHA256:5yH4zWiUMaOK0zJT19u01gXxxyFz26NJXtx2Ko5dCKQ.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```
Your fingerprint will be different: every lab server gets fresh host keys. Before typing `yes`, compare it with the real one, read from the server's own console. In a second terminal on your computer:
```bash
docker exec bastion ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```
Same fingerprint? Type `yes`, then asha's password. On the bastion:
```bash
hostname -I
exit
```
```
203.0.113.10 10.0.1.10
```
Back on the laptop:
```bash
ls -l ~/.ssh
cat ~/.ssh/known_hosts
ssh-keygen -F 203.0.113.10
```

### 3. Log in with a key
```bash
ssh-keygen -t ed25519 -C "asha@example.com"        # Enter for the default file, then a passphrase twice
ls -l ~/.ssh
cat ~/.ssh/id_ed25519.pub
ssh-copy-id asha@203.0.113.10                       # one last password login
ssh asha@203.0.113.10                               # now it asks for the key's passphrase
```
On the bastion, look at the permissions and the key:
```bash
ls -ld ~/.ssh ~/.ssh/authorized_keys
cat ~/.ssh/authorized_keys
exit
```
```
drwx------ 2 asha asha 4096 ... /home/asha/.ssh
-rw------- 1 asha asha   98 ... /home/asha/.ssh/authorized_keys
```
Unlock the key once with the agent:
```bash
eval "$(ssh-agent -s)"
ssh-add
ssh-add -l
ssh asha@203.0.113.10 hostname
```

### 4. Break it on purpose, then debug it
Log in and make the `.ssh` folder world-writable (777 is never the fix):
```bash
ssh asha@203.0.113.10
chmod 777 ~/.ssh
ls -ld ~/.ssh
exit
```
Now the key is ignored and ssh asks for a password. Press Ctrl-C, then look with `-v` (Ctrl-C again at the password prompt):
```bash
ssh asha@203.0.113.10
ssh -v asha@203.0.113.10
```
The server's log knows why. Log in with the password (still allowed for now):
```bash
ssh asha@203.0.113.10
journalctl -u ssh -n 4 --no-pager
chmod 700 ~/.ssh
ls -ld ~/.ssh
exit
```
```
... Authentication refused: bad ownership or modes for directory /home/asha/.ssh
```
Confirm the key works again:
```bash
ssh -v asha@203.0.113.10 exit 2>&1 | grep -E 'Offering|accepts|Authenticated to'
```
```
Authenticated to 203.0.113.10 ([203.0.113.10]:22) using "publickey".
```

### 5. The SSH config file
```bash
nano ~/.ssh/config
```
```
Host bastion
    HostName 203.0.113.10
    User asha
    Port 22
    IdentityFile ~/.ssh/id_ed25519
```
```bash
cat ~/.ssh/config
ls -l ~/.ssh/config
ssh bastion                     # then exit
ssh bastion 'uptime'
ssh bastion echo $HOSTNAME      # laptop: your own shell expanded it first
ssh bastion 'echo $HOSTNAME'    # bastion
ssh -o ConnectTimeout=5 asha@10.0.1.11
```
The last one times out: the laptop has no route into the private network.

### 6. Through the bastion with ProxyJump
```bash
ssh -J bastion asha@10.0.1.11
```
Check web-01's fingerprint (`docker exec web-01 ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on your computer), type `yes`, then the password.
```bash
hostname -I
exit
```
Add web-01 and db-01 to `~/.ssh/config` (compare with `reference/asha-ssh-config`):
```
Host web-01
    HostName 10.0.1.11
    User asha
    ProxyJump bastion
Host db-01
    HostName 10.0.1.21
    User asha
    ProxyJump bastion
```
```bash
cat ~/.ssh/config
ssh-copy-id web-01
ssh-copy-id db-01               # check db-01's fingerprint the same way
ssh web-01 'uptime'
for h in bastion web-01 db-01; do ssh "$h" hostname; done
ssh -G web-01 | grep -E '^(user|hostname|port|proxyjump) '
```
```
user asha
hostname 10.0.1.11
port 22
proxyjump bastion
```

### 7. Copy files: scp and rsync
```bash
find site -type f
tar czf site.tar.gz site
scp site.tar.gz web-01:/tmp/
scp db-01:/etc/os-release db-01-os-release
head -2 db-01-os-release
rsync -avzn --delete site/ web-01:site/        # dry run: nothing is copied
rsync -avz --delete site/ web-01:site/
```
Change one line and delete the old page, then sync again (dry run first):
```bash
sed -i 's/one video at a time/one clear video at a time/' site/index.html
rm site/old-landing.html
rsync -avzn --delete site/ web-01:site/
rsync -avz --delete site/ web-01:site/
rsync -avz --delete site/ web-01:site/         # nothing left to send
ssh web-01 'ls site'
```
```
deleting old-landing.html
./
index.html
```

### 8. A tunnel to the database
```bash
ssh db-01 'ss -ltn | grep 5432'                # Postgres listens on localhost only
ssh -N -L 15432:localhost:5432 db-01           # leave this running
```
Open a **second** shell on the laptop from your computer (`docker exec -it laptop su - asha`) and query through the tunnel (password `demo-db-password`):
```bash
psql -h localhost -p 15432 -U allcs -d allcsvideos -c 'SELECT * FROM courses;'
```
```
 id |     title
----+---------------
  1 | DSA
  2 | System Design
  3 | Spring Boot
(3 rows)
```
Press Ctrl-C on the tunnel in the first shell, then run the same `psql` again: `Connection refused`.

### 9. Harden sshd without locking yourself out
In the **first** shell, log in to the bastion and stay logged in for this whole step:
```bash
ssh bastion
sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers) '
grep -n Include /etc/ssh/sshd_config
ls /etc/ssh/sshd_config.d/
sudo nano /etc/ssh/sshd_config.d/10-hardening.conf
```
Type it exactly like the video, with its two mistakes, to see how each one is caught:
```
# allcsvideos SSH hardening, the same on every server
PermitRootLogin no
PasswordAuthenticaton no
KbdInteractiveAuthentication no
AllowUsers ahsa priya
```
Test before restarting:
```bash
cat /etc/ssh/sshd_config.d/10-hardening.conf
sudo sshd -t
```
```
/etc/ssh/sshd_config.d/10-hardening.conf: line 3: Bad configuration option: PasswordAuthenticaton
```
```bash
sudo sed -i 's/Authenticaton/Authentication/' /etc/ssh/sshd_config.d/10-hardening.conf
sudo sshd -t && echo "syntax OK"
sudo systemctl restart ssh
systemctl is-active ssh
```
Now the test that matters: a **new** login from the second shell on the laptop. That shell has no agent, so run `eval "$(ssh-agent -s)"` and `ssh-add` there once (or type the key passphrase when asked):
```bash
ssh bastion
```
```
asha@203.0.113.10: Permission denied (publickey).
```
Your open session in the first shell saves the day:
```bash
journalctl -u ssh -n 2 --no-pager
grep AllowUsers /etc/ssh/sshd_config.d/10-hardening.conf
sudo sed -i 's/ahsa/asha/' /etc/ssh/sshd_config.d/10-hardening.conf
sudo sshd -t && sudo systemctl restart ssh
sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|allowusers) '
```
From the second shell, verify:
```bash
ssh bastion hostname
ssh -o PubkeyAuthentication=no bastion          # Permission denied (publickey)
ssh root@203.0.113.10                           # Permission denied (publickey)
```
Roll the same file out to web-01, and to db-01 with `AllowUsers asha` only (`ssh -t` gives sudo a terminal for the password):
```bash
scp bastion:/etc/ssh/sshd_config.d/10-hardening.conf .
scp 10-hardening.conf web-01:
ssh -t web-01 'sudo install -m 644 10-hardening.conf /etc/ssh/sshd_config.d/ && sudo sshd -t && sudo systemctl restart ssh'
sed -i 's/^AllowUsers .*/AllowUsers asha/' 10-hardening.conf
scp 10-hardening.conf db-01:
ssh -t db-01 'sudo install -m 644 10-hardening.conf /etc/ssh/sshd_config.d/ && sudo sshd -t && sudo systemctl restart ssh'
for h in web-01 db-01; do ssh $h 'hostname; grep AllowUsers /etc/ssh/sshd_config.d/10-hardening.conf'; done
```

### 10. Give Priya access, the right way
Open Priya's laptop from your computer:
```bash
docker exec -it priya-laptop su - priya
```
As priya, make her own key pair:
```bash
ssh-keygen -t ed25519 -C "priya@example.com"
cat ~/.ssh/id_ed25519.pub
```
She "sends" only the public key. On your computer:
```bash
./lab/send-priya-key.sh
```
Back on Asha's laptop, install it on the bastion and web-01 (not db-01):
```bash
cat priya.pub
for h in bastion web-01; do scp priya.pub $h: ; done
ssh -t bastion 'sudo install -d -m 700 -o priya -g priya /home/priya/.ssh && sudo install -m 600 -o priya -g priya priya.pub /home/priya/.ssh/authorized_keys'
ssh -t web-01 'sudo install -d -m 700 -o priya -g priya /home/priya/.ssh && sudo install -m 600 -o priya -g priya priya.pub /home/priya/.ssh/authorized_keys'
ssh web-01 'sudo ls -la /home/priya/.ssh'       # fails: no terminal for sudo's password
ssh -t web-01 'sudo ls -la /home/priya/.ssh'
```
On Priya's laptop, write `~/.ssh/config` (see `reference/priya-ssh-config`), then:
```bash
cat ~/.ssh/config
eval "$(ssh-agent -s)"
ssh-add
ssh web-01 hostname
ssh db-01 hostname
```
At each fingerprint prompt, paste the fingerprint from `docker exec <server> ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` instead of `yes`: ssh compares them for you. web-01 answers; db-01 says `Permission denied (publickey)`. On Asha's laptop:
```bash
ssh db-01 'journalctl -u ssh --no-pager | grep priya'
```
```
... User priya from 10.0.1.10 not allowed because not listed in AllowUsers
```

### 11. Pitfall: the host key changed
Stage it by giving web-01 brand-new host keys, from Asha's laptop:
```bash
ssh -t web-01 'sudo rm /etc/ssh/ssh_host_* && sudo ssh-keygen -A && sudo systemctl restart ssh'
ssh web-01
```
```
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
...
Host key verification failed.
```
Check the new fingerprint on the console first (on your computer), and only then remove the old entry and reconnect:
```bash
docker exec web-01 ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```
```bash
ssh-keygen -R 10.0.1.11
ssh web-01 hostname                             # paste the verified fingerprint at the prompt
```

## Common mistakes
- **Deleting the known_hosts line without checking.** "REMOTE HOST IDENTIFICATION HAS CHANGED" is the check that stops a man-in-the-middle attack. Verify the new fingerprint first.
- **`StrictHostKeyChecking=no` in scripts.** It switches that safety check off for good. Add the known host keys instead.
- **Wrong permissions** (like `777` on `~/.ssh`). The server quietly ignores your key; read its log (`journalctl -u ssh`).
- **Restarting sshd with no test and no second session open.** Always `sudo sshd -t` first, keep one session logged in, and test with a brand-new login.
- **Copying a private key to the bastion, or turning on agent forwarding.** Anyone with root there could use your key. `ProxyJump` keeps every key on your laptop.
- **Moving SSH off port 22 and calling it security.** It cuts bot noise, but any port scan finds the new port. Keys only, no root, and a bastion are what protect you.

## Clean up
```bash
./lab/down.sh
```
This removes the five containers, the `ssh-public` and `ssh-private` networks, and the `ssh-lab-sshd:1` and `ssh-lab-db:1` images. Nothing was written outside the containers.

## Next
M03-L01 · Bash Basics: [../../scripts/m03-l01-bash-basics](../../scripts/m03-l01-bash-basics)
