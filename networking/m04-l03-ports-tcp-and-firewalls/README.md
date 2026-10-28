# M04-L03 · Ports, TCP and Firewalls
> Video: Module 4, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- Ports, privileged ports below 1024, the ephemeral range, and the five-tuple that tells connections apart.
- Find what's listening, and on which address, with `sudo ss -tulpn` (and why `127.0.0.1` means "this machine only").
- Watch a real TCP handshake, FIN close, TIME_WAIT, UDP's fire-and-forget, and a reset with `tcpdump`.
- The difference between **connection refused** (nothing listening) and **connection timed out** (something dropped the packet).
- Build a ufw firewall without locking yourself out, see the iptables/nftables rules it writes, and fix rule order.
- NAT on a Linux router: MASQUERADE to let private servers out, DNAT port forwarding to let visitors in, and how `docker run -p` uses the same DNAT.

## Before you start
- Docker Desktop running. The lab is seven Ubuntu 24.04 containers with `ss`, `ufw`, `iptables`, `nftables`, `nc`, `curl`, `tcpdump`, `nginx` and `ssh` installed with apt.
- The SSH lesson (module 2) and [M04-L01](../m04-l01-ip-addresses-subnets-and-cidr/) (subnets, gateways). If another module 4 lab is still running, stop it first with its `lab/down.sh`.
- For step 15 only: the `nginx:1.29-alpine` image (pulled automatically).

## Files in this folder
| File | What it is |
|------|------------|
| `copilot.py` | The Course Copilot stand-in: answers `GET /health` on port 8000; its default host is `127.0.0.1` |
| `lab/Dockerfile` | Lab image: Ubuntu 24.04 + the tools above, user `asha` with sudo |
| `lab/up.sh` | Creates the three networks and seven machines, sets the course addresses, starts nginx, sshd and Copilot (bound to 127.0.0.1, on purpose) |
| `lab/bot.sh` | `start` / `stop` the bot at 192.0.2.66 that hammers `POST /login` |
| `lab/down.sh` | Removes everything the lab created |
| `lab/files/allcsvideos.conf` | nginx site on web-01: the storefront on port 80; `/login` always answers 401 |
| `lab/files/index.html` | The storefront page |
| `lab/files/mirror.conf` | nginx site for the "package mirror" on the lab internet |

The lab:

| Network | Range | Machines |
|---------|-------|----------|
| the internet | `192.0.2.0/24` | isp `.1` (stands in for internet routers), Lukas's laptop `.50`, bot `.66`, package mirror `.80` |
| allcsvideos public side | `203.0.113.0/24` | router (NAT box) `.1`, bastion `.10`, isp `.254` |
| private subnet A | `10.0.1.0/24` | router (gateway) `.1`, bastion `.10`, web-01 `.11` |

Like the real internet, isp has no route to private `10.x` addresses.

## Follow along

1. Start the lab and open Asha's two terminals:
   ```bash
   bash lab/up.sh
   ```
   **Terminal A** (Asha on web-01, over SSH from the bastion):
   ```bash
   docker exec -it -u asha bastion bash
   ssh web-01
   ```
   **Terminal B** (Asha's second terminal, on the bastion): `docker exec -it -u asha bastion bash`

2. The hook. In **A** (web-01), then in **B** (bastion):
   ```bash
   curl -s localhost:8000/health          # A: {"status": "ok"}
   ```
   ```bash
   curl 10.0.1.11:8000/health             # B
   ```
   ```
   curl: (7) Failed to connect to 10.0.1.11 port 8000 after 0 ms: Couldn't connect to server
   ```
   Works on the server, fails instantly from everywhere else.

3. Ports. In **A**:
   ```bash
   cat /proc/sys/net/ipv4/ip_local_port_range
   python3 -m http.server 80
   sysctl net.ipv4.ip_unprivileged_port_start
   ps -o user,pid,cmd -C nginx
   ```
   You should see the ephemeral range `32768	60999`, then `PermissionError: [Errno 13] Permission denied`,
   `net.ipv4.ip_unprivileged_port_start = 1024`, and nginx's master running as `root` with a worker as `www-data`.

4. Who is listening? In **A**:
   ```bash
   sudo ss -tulpn
   ```
   ```
   Netid    State     Recv-Q     Send-Q         Local Address:Port          Peer Address:Port    Process
   tcp      LISTEN    0          511                  0.0.0.0:80                 0.0.0.0:*        users:(("nginx",...
   tcp      LISTEN    0          128                  0.0.0.0:22                 0.0.0.0:*        users:(("sshd",...
   tcp      LISTEN    0          5                  127.0.0.1:8000               0.0.0.0:*        users:(("python3",...
   tcp      LISTEN    0          511                     [::]:80                    [::]:*        ...
   tcp      LISTEN    0          128                     [::]:22                    [::]:*        ...
   ```
   (Two rows on `127.0.0.11` belong to Docker's DNS helper; ignore them.) Copilot listens on `127.0.0.1`: loopback only.

5. The fix: restart Copilot on all addresses. In **A**, then check from **B**:
   ```bash
   pkill -f copilot.py
   python3 copilot.py --host 0.0.0.0 &
   sudo ss -tlpn 'sport = :8000'
   ```
   ```bash
   curl -s 10.0.1.11:8000/health          # B: {"status": "ok"}
   ```
   No firewall was involved: nothing was listening on the address the bastion called.

6. Watch a TCP connection. In **A** start a capture, in **B** make one request, then press Ctrl-C in **A**:
   ```bash
   sudo tcpdump -n -t -i eth0 tcp port 80                         # A
   ```
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' http://10.0.1.11/      # B: 200
   ```
   You should see 10 packets (trimmed):
   ```
   IP 10.0.1.10.47336 > 10.0.1.11.80: Flags [S], ...           <- SYN
   IP 10.0.1.11.80 > 10.0.1.10.47336: Flags [S.], ...          <- SYN-ACK
   IP 10.0.1.10.47336 > 10.0.1.11.80: Flags [.], ack 1, ...    <- ACK
   IP 10.0.1.10.47336 > 10.0.1.11.80: Flags [P.], ... HTTP: GET / HTTP/1.1
   IP 10.0.1.11.80 > 10.0.1.10.47336: Flags [P.], ... HTTP: HTTP/1.1 200 OK
   IP 10.0.1.10.47336 > 10.0.1.11.80: Flags [F.], ...          <- FIN
   IP 10.0.1.11.80 > 10.0.1.10.47336: Flags [F.], ...          <- FIN
   ```
   Your ephemeral port will differ.

7. Connection states:
   ```bash
   ss -tan state established        # A: one connection on :22, from the bastion (your SSH session)
   ```
   ```bash
   ss -tan state time-wait          # B: the connections it just closed, to :8000 and :80
   ```

8. UDP. In **A** listen, in **B** send, then Ctrl-C in **A**:
   ```bash
   nc -ul 9000                                          # A: "hello" arrives
   ```
   ```bash
   echo hello | nc -u -w1 10.0.1.11 9000                # B
   ```
   Now send to a port where nothing listens. In **A** capture, in **B** send, then Ctrl-C:
   ```bash
   sudo tcpdump -n -t -i eth0 udp                       # A
   ```
   ```bash
   echo hello | nc -u -w1 10.0.1.11 9001; echo "exit code $?"   # B: exit code 0
   ```
   tcpdump shows one `UDP, length 6` packet; the sender gets no error at all.

9. A refused connection. In **A** capture, in **B** connect, then Ctrl-C:
   ```bash
   sudo tcpdump -n -t -i eth0 tcp port 9000             # A
   ```
   ```bash
   time nc -zv 10.0.1.11 9000                           # B: Connection refused, in about 1 ms
   ```
   ```
   IP 10.0.1.10.34940 > 10.0.1.11.9000: Flags [S], ...
   IP 10.0.1.11.9000 > 10.0.1.10.34940: Flags [R.], ...     <- reset: nothing listens
   ```

10. ufw, including the classic mistake (made on purpose). In **A**:
    ```bash
    sudo ufw status verbose                  # Status: inactive
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw enable                          # answer y to "Command may disrupt existing ssh connections"
    sudo ufw status
    hostname
    ```
    Your open session still works (`web-01`). But a **new** login from **B**:
    ```bash
    ssh -o ConnectTimeout=5 web-01
    ```
    ```
    ssh: connect to host 10.0.1.11 port 22: Connection timed out
    ```
    Fix it from the open session (**A**), then try again from **B**:
    ```bash
    sudo ufw limit 22/tcp                    # A: Rule added / Rule added (v6)
    ```
    ```bash
    ssh web-01 hostname                      # B: web-01
    ```
    Add the web and the internal Copilot rule (**A**):
    ```bash
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow from 10.0.1.0/24 to any port 8000 proto tcp
    sudo ufw status verbose
    ```
    ```
    Default: deny (incoming), allow (outgoing), deny (routed)
    22/tcp                     LIMIT IN    Anywhere
    80/tcp                     ALLOW IN    Anywhere
    443/tcp                    ALLOW IN    Anywhere
    8000/tcp                   ALLOW IN    10.0.1.0/24
    22/tcp (v6)                LIMIT IN    Anywhere (v6)
    ...
    ```

11. A real timeout. In **A** capture port 9000, in **B** connect, then Ctrl-C in **A**:
    ```bash
    sudo tcpdump -n -t -i eth0 tcp port 9000             # A
    ```
    ```bash
    time nc -zv -w 5 10.0.1.11 9000                      # B: timed out after 5 s
    curl -s 10.0.1.11:8000/health                        # B: still {"status": "ok"}
    ```
    tcpdump shows the SYN resent about once a second and nothing coming back. Only the firewall changed.

12. What ufw actually wrote (**A**):
    ```bash
    sudo iptables -V
    sudo iptables -S INPUT
    sudo nft list chain ip filter ufw-user-input
    sudo iptables -S ufw-before-input | head -n 3
    ```
    `iptables v1.8.10 (nf_tables)`, a `DROP` policy, your rules in `ufw-user-input` (22 through a `recent` match = the rate limit),
    and the reason your session survived:
    ```
    -A ufw-before-input -i lo -j ACCEPT
    -A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    ```

13. NAT. web-01 tries the package mirror on the internet (**A**):
    ```bash
    curl -sS --max-time 5 http://192.0.2.80/      # curl: (28) Connection timed out after 5008 milliseconds
    ```
    Open a terminal on the **router** (`docker exec -it -u asha router bash`):
    ```bash
    ip -br a show eth0
    ip -br a show eth1
    ip route
    sysctl net.ipv4.ip_forward
    sudo iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -o eth0 -j MASQUERADE
    ```
    Try again in **A** (`Ubuntu package mirror (lab)`), then look at the mirror's log from your laptop:
    ```bash
    docker exec mirror tail -n 1 /var/log/nginx/access.log
    ```
    ```
    203.0.113.1 - - [...] "GET / HTTP/1.1" 200 28 "-" "curl/8.5.0"
    ```
    The mirror only ever sees the router's public address. Now the other direction. Open **Lukas's** laptop
    (`docker exec -it -u lukas lukas bash`):
    ```bash
    curl -sS --max-time 5 http://203.0.113.1/     # Couldn't connect to server
    ```
    Port forwarding on the **router**:
    ```bash
    sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination 10.0.1.11:80
    sudo iptables -t nat -S
    ```
    Lukas tries again (`curl -sS http://203.0.113.1/` shows the storefront), and web-01 sees his real address (**A**):
    ```bash
    sudo tail -n 1 /var/log/nginx/access.log      # 192.0.2.50 - - [...] "GET / HTTP/1.1" 200 ...
    ```

14. Block the bot. Start it from your laptop and wait about 40 seconds:
    ```bash
    bash lab/bot.sh start
    ```
    In **A**:
    ```bash
    sudo tail -n 3 /var/log/nginx/access.log
    sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn
    sudo ufw deny from 192.0.2.66
    sudo grep -c 192.0.2.66 /var/log/nginx/access.log
    ```
    Wait a few seconds and count again: it is still growing. Why?
    ```bash
    sudo ufw status numbered
    ```
    ```
    [ 2] 80/tcp                     ALLOW IN    Anywhere
    ...
    [ 5] Anywhere                   DENY IN     192.0.2.66
    ```
    The first matching rule wins. Move the deny to the top:
    ```bash
    sudo ufw delete 5                        # answer y
    sudo ufw insert 1 deny from 192.0.2.66
    sudo ufw status numbered
    sudo grep -c 192.0.2.66 /var/log/nginx/access.log
    sudo grep -c 192.0.2.66 /var/log/nginx/access.log     # a few seconds later: same number
    sudo nft list chain ip filter ufw-user-input | head -n 4
    ```
    The drop rule's counter goes up (`ip saddr 192.0.2.66 counter packets 10 ... drop`). From the bot's side
    (`docker exec -it bot bash`), `curl -sS --max-time 5 -X POST http://203.0.113.1/login` now times out,
    while Lukas's `curl -sS http://203.0.113.1/` still works. Stop the bot:
    ```bash
    bash lab/bot.sh stop
    ```

15. `docker run -p` is DNAT. On your laptop:
    ```bash
    docker run -d --rm -p 8080:80 --name web-publish nginx:1.29-alpine
    docker run --rm --net=host --cap-add NET_ADMIN ports-lab:m04l03 sh -c 'iptables -t nat -S DOCKER | grep 8080'
    docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' web-publish
    docker rm -f web-publish
    ```
    ```
    -A DOCKER -p tcp -m tcp --dport 8080 -j DNAT --to-destination 172.17.0.2:80
    172.17.0.2
    ```
    The same kind of rule as on our router. On a Linux server, published ports take this path before ufw's input rules see the traffic (module 6 comes back to this).

16. Pitfall checks. In **A** (on web-01 itself):
    ```bash
    nc -zv 10.0.1.11 9000              # refused here, but timed out from the bastion: ufw always allows loopback
    grep IPV6= /etc/default/ufw        # IPV6=yes: ufw writes v6 rules too
    ```
    On the **router**:
    ```bash
    sudo iptables -S FORWARD           # -P FORWARD ACCEPT
    sudo ip6tables -S                  # empty, every policy ACCEPT
    ```

## Common mistakes
- **Binding to localhost.** The service works on the server and nowhere else. `ss -tulpn` shows the bound address in a second.
- **Enabling the firewall before allowing SSH.** Keep a session open and allow SSH first; on a cloud server with no console, this is how people lock themselves out.
- **Firewall order.** The first matching rule wins, so a deny below an allow does nothing. Check `ufw status numbered` and `ufw insert`.
- **Forgetting IPv6.** ufw writes both (`IPV6=yes`), but plain `iptables` rules cover IPv4 only; `ip6tables` is separate. A real NAT box also filters what it forwards.
- **Testing from the wrong place.** A machine talking to itself uses loopback, which ufw always allows. Test from where your users are.
- **Docker published ports bypass ufw** on a Linux server (DNAT happens first).

## Clean up
```bash
bash lab/down.sh
docker image rm nginx:1.29-alpine     # optional
```

## Next
[M04-L04 · HTTP, TLS and Certificates](../m04-l04-http-tls-and-certificates/)
