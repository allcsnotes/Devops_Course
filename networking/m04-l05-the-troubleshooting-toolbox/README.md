# M04-L05 · The Troubleshooting Toolbox
> Video: Module 4, Lesson 5. Watch it first, then follow along here.

## What you'll learn
- A seven-step, outside-in method for "the site is down": is it just me, DNS, reachability, the port, TLS, HTTP, logs.
- The tools for each step: `curl` (`-I`, `-v`, `-w`, `--resolve`), `dig`, `ping`, `traceroute`/`tracepath`/`mtr`, `ss`, `nc`, `tcpdump`.
- How to read curl's phase timings to tell network, TLS and server time apart.
- How each symptom points to its layer: host unreachable, timeout, refused, exit code 60, 502, 504, slow.
- A one-page runbook you can reuse: [`site-down-runbook.md`](site-down-runbook.md).

## Before you start
- Docker Desktop running. The lab is six Ubuntu 24.04 containers with every tool installed with apt
  (the video saw curl 8.5.0, nginx 1.24.0, BIND/dig 9.18.39, mtr 0.95, tcpdump 4.99.4, traceroute 2.1.5, iptables 1.8.10).
- Everything from module 4: addresses and routes ([L01](../m04-l01-ip-addresses-subnets-and-cidr/)), DNS ([L02](../m04-l02-dns-in-practice/)),
  ports and firewalls ([L03](../m04-l03-ports-tcp-and-firewalls/)), HTTPS and nginx ([L04](../m04-l04-http-tls-and-certificates/)).
  If another module 4 lab is still running, stop it first with its `lab/down.sh`.

## Files in this folder
| File | What it is |
|------|------------|
| `site-down-runbook.md` | The "site is down" runbook: seven rows (question, commands, healthy, if it fails) and the rules |
| `curl-format.txt` | curl `-w` format file: every phase timing plus the status code |
| `lab/Dockerfile` | Lab image: Ubuntu 24.04 + the toolbox + BIND, nginx, python3 |
| `lab/up.sh` / `lab/down.sh` | Build / remove the lab |
| `lab/break.sh` | Stages each incident (`1`, `2`, `2b`, `3`, `3b`, `4`, `4b`, `5`, `5b`, `icmp`), as was done off camera |
| `lab/ns1/` | BIND config and the `allcsvideos.test` zone (TTL 300) |
| `lab/proxy/allcsvideos.conf` | nginx on proxy-01: 301 to HTTPS, TLS, `/api/` to api-01 with `proxy_read_timeout 5s`, a `timing` access-log format with `rt=` and `urt=` |
| `lab/proxy/mkcerts.sh` | Makes the lab CA and three certificates inside proxy-01: good, expired, staging (lab-only keys) |
| `lab/web/index.html`, `lab/api/api.py` | Storefront and API stand-ins; the API sleeps for the seconds in `/etc/api-delay` |

The lab:

| Network | Machines |
|---------|----------|
| outside `10.0.55.0/24` | router `.1`, laptop `.50` (Asha, on the same side of the internet as Lukas), ns1 `.53` |
| inside `10.0.56.0/24` | router `.1`, proxy-01 `.10` (nginx, TLS), web-01 `.20` (storefront), api-01 `.30` (API) |

## Follow along

1. Start the lab and open terminals as needed (the prompt shows the machine):
   ```bash
   bash lab/up.sh
   docker exec -it -u asha laptop bash      # also: router, ns1, proxy01, api01
   ```

2. The baseline, with the format file (**laptop**):
   ```bash
   cat curl-format.txt
   curl -s -o /dev/null -w @curl-format.txt https://allcsvideos.test/
   ```
   ```
      namelookup:  0.001096s
         connect:  0.001260s
      appconnect:  0.011968s
     pretransfer:  0.011985s
   starttransfer:  0.014679s
           total:  0.014715s
            code:  200
   ```
   Everything runs on one machine, so the times are tiny. Remember the shape, not the numbers.

3. The tools tour. **curl** (**laptop**):
   ```bash
   curl -I https://allcsvideos.test/
   curl -sI http://allcsvideos.test/ | head -3
   curl -v https://allcsvideos.test/
   curl -s -o /dev/null -w '%{http_code} %{remote_ip}\n' https://allcsvideos.test/
   curl -s -o /dev/null -w '%{http_code} %{remote_ip}\n' --resolve allcsvideos.test:443:10.0.56.10 https://allcsvideos.test/
   curl -s -o /dev/null -w '%{http_code}\n' https://10.0.56.10/; echo exit $?
   ```
   `200 OK` with `Server: nginx/1.24.0 (Ubuntu)`; `301 Moved Permanently` on port 80; the TLS 1.3 handshake and
   `SSL certificate verify ok` in `-v`; `200 10.0.56.10` twice; and `000` / `exit 60` for the bare IP (the certificate is for the name).
   `-k` skips the certificate check: fine for one quick question, never in a script.

   **dig, ping, traceroute, tracepath, mtr** (**laptop**):
   ```bash
   dig +short allcsvideos.test
   dig +short @10.0.55.53 www.allcsvideos.test
   dig allcsvideos.test +noall +answer
   ping -c 4 10.0.56.10
   traceroute -n 10.0.56.10
   tracepath -n 10.0.56.10
   mtr -n --report -c 10 10.0.56.10
   ```
   `10.0.56.10` with TTL `300`; `ttl=63` and `0% packet loss`; hop 1 `10.0.55.1`, hop 2 `10.0.56.10`; `pmtu 1500`.

   **nc** (**laptop**):
   ```bash
   nc -zv 10.0.56.10 443        # succeeded!
   nc -zv 10.0.56.10 22         # Connection refused
   ```
   **ss** (**proxy01**; run `ss -tan` right after two curls from the laptop):
   ```bash
   sudo ss -tulpn
   ss -tan
   ```
   nginx on `0.0.0.0:443` and `:80` (the `127.0.0.11` rows are Docker's DNS helper). `ss -tan` shows two `TIME-WAIT`
   entries with the laptop on 443 and one from the proxy to `10.0.56.30:8080`: two connections per request, that's a reverse proxy.

   **tcpdump** (**proxy01**; while it waits, run `curl -s -o /dev/null https://allcsvideos.test/` on the **laptop**):
   ```bash
   sudo tcpdump -n -t -i any -c 6 host 10.0.55.50 and port 443
   sudo tcpdump -n -i any -c 20 -w /tmp/site.pcap 'port 443 or port 8080'
   ls -l /tmp/site.pcap
   tcpdump -n -t -r /tmp/site.pcap 'port 8080'
   ```
   The first shows `eth0 In ... Flags [S]`, `eth0 Out ... Flags [S.]`, `Flags [.]`, then `Flags [P.]` (the TLS hello).
   Reading the pcap back for port 8080 shows the proxy's plain-HTTP leg: `HTTP: GET / HTTP/1.0` and `HTTP/1.0 200 OK`. TLS ends at the proxy.
   For deeper analysis, copy the pcap to your computer (`docker cp proxy01:/tmp/site.pcap .`) and open it in Wireshark.

4. **Incident 1: www doesn't load.** Stage it from your computer: `bash lab/break.sh 1`. Then on the **laptop**:
   ```bash
   curl -sS https://www.allcsvideos.test/
   curl -sS -o /dev/null -w '%{http_code}\n' https://allcsvideos.test/
   curl -sS -o /dev/null -w '%{http_code}\n' https://allcsvideos.test/api/health
   dig +short allcsvideos.test
   dig +short www.allcsvideos.test
   curl -sS -o /dev/null -w '%{http_code}\n' --resolve www.allcsvideos.test:443:10.0.56.10 https://www.allcsvideos.test/
   ping -c 2 10.0.56.11
   ```
   ```
   curl: (7) Failed to connect to www.allcsvideos.test port 443 after 3097 ms: Couldn't connect to server
   200
   200
   10.0.56.10
   10.0.56.11
   200
   From 10.0.55.1 icmp_seq=1 Destination Host Unreachable
   ```
   The bare domain works, `www` points at the retired address. Fix it on **ns1**:
   ```bash
   grep -nE "serial|IN A" /etc/bind/zones/db.allcsvideos.test
   sudo sed -i -e 's/^www     IN A    10.0.56.11/www     IN A    10.0.56.10/' -e 's/2026102002 ; serial/2026102003 ; serial/' /etc/bind/zones/db.allcsvideos.test
   grep -nE "serial|^www" /etc/bind/zones/db.allcsvideos.test
   sudo named-checkzone allcsvideos.test /etc/bind/zones/db.allcsvideos.test
   sudo rndc reload allcsvideos.test
   ```
   Back on the **laptop**: `dig +short www.allcsvideos.test` gives `10.0.56.10` and the curl gives `200`.

5. **Incident 2: a timeout.** `bash lab/break.sh 2`. On the **laptop**:
   ```bash
   curl -sS --connect-timeout 5 https://allcsvideos.test/
   dig +short allcsvideos.test
   ping -c 3 10.0.56.10
   nc -zv -w 5 10.0.56.10 443
   nc -zv -w 5 10.0.56.10 80
   sudo traceroute -n -T -p 443 -m 4 10.0.56.10
   ```
   `curl: (28) ... after 5006 ms: Timeout was reached`, DNS fine, ping fine, 443 `timed out` but 80 `succeeded`, and the TCP
   traceroute dies after hop 1. On **proxy01** nginx is listening, yet nothing arrives (keep a `curl` running on the laptop meanwhile):
   ```bash
   sudo ss -tlnp | grep nginx
   sudo timeout 8 tcpdump -n -i any port 443          # 0 packets captured
   ```
   On the **router**:
   ```bash
   sudo timeout 8 tcpdump -n -i eth1 port 443          # 0 packets: the wrong interface to look at
   sudo tcpdump -n -t -i any -c 3 port 443             # eth0 In ... Flags [S], three times
   sudo iptables -L FORWARD -n -v --line-numbers
   sudo iptables -D FORWARD 1
   sudo iptables -L FORWARD -n --line-numbers
   ```
   Rule 1 was `DROP ... 10.0.56.10 tcp dpt:443`. After deleting it, the laptop gets `200`.

   **2b, refused instead.** `bash lab/break.sh 2b`. On the **laptop**:
   ```bash
   curl -sS --connect-timeout 5 https://allcsvideos.test/     # (7) ... after 0 ms
   nc -zv -w 5 10.0.56.10 443                                 # Connection refused
   ```
   On **proxy01** (no systemd in the lab; on a real server check `journalctl`, then `systemctl start nginx`):
   ```bash
   sudo ss -tlnp
   sudo nginx -t
   sudo nginx
   sudo ss -tlnp | grep nginx
   ```
   Timeout: look along the path. Refused: look at the server itself.

6. **Incident 3: certificate problems.** `bash lab/break.sh 3`. On the **laptop**:
   ```bash
   curl -sS https://allcsvideos.test/
   nc -zv 10.0.56.10 443
   openssl s_client -connect allcsvideos.test:443 -servername allcsvideos.test </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
   openssl s_client -connect allcsvideos.test:443 -servername allcsvideos.test </dev/null 2>/dev/null | grep "Verify return"
   date -u
   curl -sk -o /dev/null -w '%{http_code}\n' https://allcsvideos.test/
   ```
   `curl: (60) SSL certificate problem: certificate has expired`, `notAfter` is yesterday, `Verify return code: 10 (certificate has expired)`,
   and with `-k` the site itself answers `200`. Deploy the renewed certificate on **proxy01** (reload, not restart):
   ```bash
   sudo cp /root/ca/good.crt /etc/nginx/tls/allcsvideos.crt
   sudo nginx -t
   sudo nginx -s reload
   ```
   Check the dates again and curl without `-k`: `200`.

   **3b, wrong name.** `bash lab/break.sh 3b`. On the **laptop**:
   ```bash
   curl -sS https://allcsvideos.test/
   openssl s_client -connect allcsvideos.test:443 -servername allcsvideos.test </dev/null 2>/dev/null | openssl x509 -noout -ext subjectAltName
   ```
   `no alternative certificate subject name matches target host name 'allcsvideos.test'`; the only SAN is `DNS:staging.allcsvideos.test`.
   Put the right certificate and key back on **proxy01**:
   ```bash
   sudo cp /root/ca/good.crt /etc/nginx/tls/allcsvideos.crt
   sudo cp /root/ca/site.key /etc/nginx/tls/allcsvideos.key
   sudo nginx -t && sudo nginx -s reload
   ```

7. **Incident 4: 502 Bad Gateway.** `bash lab/break.sh 4`. On the **laptop**:
   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' https://allcsvideos.test/
   curl -sS https://allcsvideos.test/api/health
   ```
   `200` for the home page, an nginx `502 Bad Gateway` page for the API. A 502 comes from the proxy: read its log (**proxy01**):
   ```bash
   sudo tail -n 1 /var/log/nginx/error.log
   nc -zv 10.0.56.30 8080
   ```
   `connect() failed (111: Connection refused) while connecting to upstream ... upstream: "http://10.0.56.30:8080/api/health"`.
   On **api01**:
   ```bash
   sudo ss -tlnp
   tail -n 2 /var/log/api.log
   ```
   Nothing on 8080. Restart the API (from your computer: `bash lab/break.sh api-up`), then on **api01** `sudo ss -tlnp | grep 8080`
   shows python3 again, and the laptop's `/api/health` gives `200`.

   **4b, 504 Gateway Timeout.** On **api01** make the API slow, then on the **laptop**:
   ```bash
   echo 8 > /etc/api-delay                                              # api01
   ```
   ```bash
   curl -sS -o /dev/null -w '%{http_code} %{time_total}s\n' https://allcsvideos.test/api/courses     # laptop: 504 5.02...s
   ```
   On **proxy01**:
   ```bash
   sudo tail -n 1 /var/log/nginx/error.log
   sudo tail -n 1 /var/log/nginx/access.log
   grep -n proxy_read_timeout /etc/nginx/sites-enabled/allcsvideos
   ```
   `upstream timed out (110: Connection timed out) while reading response header`, `504 rt=5.012 urt=5.013`, and
   `18:        proxy_read_timeout 5s;` (nginx's default is 60s; the lab uses 5). On **api01**:
   ```bash
   grep -E "Exception|BrokenPipe" /var/log/api.log
   echo 0 > /etc/api-delay
   ```
   The API finished its work later and found nobody waiting: `BrokenPipeError`. With the delay back at 0 the laptop gets `200 0.0126...s`.

8. **Incident 5: slow, not broken.** `bash lab/break.sh 5`. On the **laptop**:
   ```bash
   curl -s -o /dev/null -w @curl-format.txt https://allcsvideos.test/api/courses
   curl -s -o /dev/null -w @curl-format.txt https://allcsvideos.test/
   ```
   For the API, everything up to `pretransfer` is ~0.011s but `starttransfer` is `1.52s`: the server's time. The home page through
   the same proxy is fast, so it's the API, not nginx. Confirm on **proxy01** and **api01**, then reset:
   ```bash
   sudo tail -n 2 /var/log/nginx/access.log        # proxy01: "GET /api/courses ..." 200 rt=1.509 urt=1.509
   ```
   ```bash
   tail -n 1 /var/log/api.log                      # api01: GET /api/courses 200 1.508s
   echo 0 > /etc/api-delay
   ```
   **5b, a slow network.** On the **router** (netem needs the NET_ADMIN capability, which the lab gives it):
   ```bash
   ip -br -4 addr show eth0
   sudo tc qdisc add dev eth0 root netem delay 100ms
   tc qdisc show dev eth0
   ```
   On the **laptop**:
   ```bash
   curl -s -o /dev/null -w @curl-format.txt https://allcsvideos.test/
   ping -c 3 10.0.56.10
   mtr -n --report -c 10 10.0.56.10
   ```
   `connect 0.111`, `appconnect 0.218`, `starttransfer 0.329`: three round trips, each 100 ms slower. Ping shows ~100 ms and mtr shows the
   latency starting at hop 1. Remove it on the **router** and re-run the curl:
   ```bash
   sudo tc qdisc del dev eth0 root
   tc qdisc show dev eth0
   ```

9. **Pitfalls, for real.** ICMP blocked is not host down: `bash lab/break.sh icmp`, then on the **laptop**:
   ```bash
   ping -c 3 -W 1 10.0.56.10                                          # 100% packet loss
   curl -sS -o /dev/null -w '%{http_code}\n' https://allcsvideos.test/ # 200
   ```
   Remove it on the **router**: `sudo iptables -D FORWARD 1`.

   One vantage point is not enough: `bash lab/break.sh 2` again. On **proxy01** the site looks fine, from the **laptop** it isn't:
   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' --resolve allcsvideos.test:443:127.0.0.1 https://allcsvideos.test/    # proxy01: 200
   ```
   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' --connect-timeout 5 https://allcsvideos.test/    # laptop: (28) ... 000
   ```
   Remove the rule on the **router**: `sudo iptables -D FORWARD 1`.

10. Read [`site-down-runbook.md`](site-down-runbook.md) and keep it next to `curl-format.txt` for your own systems.

## Common mistakes
- **Changing many things at once.** If the site comes back you'll never know why. One change, then test.
- **Trusting one vantage point.** The server testing itself proves little. Test from where your users are.
- **ICMP blocked is not host down.** Many networks block ping; AWS security groups don't allow it unless you add a rule.
- **tcpdump on the wrong interface.** Start with `-i any`, then narrow down.
- **Leaving `curl -k` in scripts or health checks.** It hides exactly the failure you need to see.
- **"Fixing" a 504 with a bigger timeout.** Find out why the backend is slow.

## Clean up
```bash
bash lab/down.sh
```

## Next
[M05-L01 · How Git Really Works](../../git/m05-l01-how-git-really-works/)
