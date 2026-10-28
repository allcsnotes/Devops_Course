# M04-L04 · HTTP, TLS and Certificates
> Video: Module 4, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- HTTP as plain text: request line, headers, body, status families, cookies, keep-alive, HTTP/2.
- nginx as a reverse proxy: `upstream`, `proxy_pass`, the `Host` / `X-Forwarded-*` headers, and what a 502 means.
- Why plain HTTP leaks passwords and cookies, and how the TLS 1.3 handshake fixes it.
- Certificate chains: build your own root, intermediate and server certificate with `openssl`, and fix the missing-intermediate bug.
- Let's Encrypt's ACME protocol with certbot (against Pebble, its offline test server), HTTP-to-HTTPS redirect and HSTS.
- Expired certificates: see one fail, monitor expiry with `cert-check`, and automate renewal with a timer and a deploy hook.

## Before you start
- Docker Desktop running. The lab is Ubuntu 24.04 machines with nginx 1.24, OpenSSL 3.0, curl 8.5 and certbot 2.9 from Ubuntu's packages,
  plus `ghcr.io/letsencrypt/pebble:2.10.1` and `ghcr.io/letsencrypt/pebble-challtestsrv:2.10.1` (pulled automatically).
- Ports and `tcpdump` from [M04-L03](../m04-l03-ports-tcp-and-firewalls/), and the `.test` names from [M04-L02](../m04-l02-dns-in-practice/).
  If another module 4 lab is still running, stop it first with its `lab/down.sh`.
- `cert-check` follows the style of the health-check toolkit from the module 3 build (same exit codes).
- **Every key in this lab is a lab-only key**, created inside throwaway containers. Never reuse them, and only trust a private root on machines you control.

## Files in this folder
| File | What it is |
|------|------------|
| `nginx/allcsvideos-v1.conf` | First proxy config: two `upstream`s, `/api/` to the API, everything else to the storefront |
| `nginx/allcsvideos-v2.conf` | + the four `proxy_set_header` lines |
| `nginx/allcsvideos-v3.conf` | + a 443 server block, **with the staged mistake**: `ssl_certificate` is `www.crt` alone |
| `nginx/allcsvideos-v3b.conf` | The fix: `fullchain.crt` |
| `nginx/allcsvideos-v4.conf` | Port 80 serves ACME challenges and redirects everything else (301); HSTS `max-age=300` on 443 |
| `nginx/allcsvideos-v5.conf` | Same, pointing at the Let's Encrypt (Pebble) files in `/etc/letsencrypt/live/` |
| `pki/int.ext`, `pki/www.ext` | Extension files for signing the intermediate and the server certificate (SANs live here) |
| `cert-check` | Days until a live site's certificate expires; exit 0 OK, 1 WARN (<21 days), 2 CRIT (<7 days or expired), 3 UNKNOWN |
| `reload-nginx` | certbot deploy hook: reloads nginx after a real renewal |
| `apps/api.py` | API stand-in: `/api/health`, `/api/whoami`, `POST /api/login`, `/api/me` (fake user and session, lab only) |
| `apps/store/` | Storefront stand-in, with a deliberate mixed-content `http://` script on line 3 |
| `lab/Dockerfile` | Lab image (Ubuntu 24.04 + the tools above; users `asha` and `lukas`) |
| `lab/up.sh` / `lab/down.sh` | Build / remove the lab |
| `lab/pass.sh` | Copies one file between two lab machines (CSR to the CA, certificates back) |
| `lab/pebble-config.json` | Pebble config with a single 90-day certificate profile |
| `lab/pebble.minica.pem` | Pebble's public test CA, which signed Pebble's own HTTPS certificate (lab only) |

The lab network `10.0.44.0/24`: web-01 `.10` (nginx + certbot), store-01 `.11` (port 3000), api-01 `.21` (port 8080),
lukas-laptop `.50`, lab-ca `.5`, lab-dns `.53`, pebble `.100`.

## Follow along

1. Start the lab, and open three terminals:
   ```bash
   bash lab/up.sh
   ```
   - **web-01**: `docker exec -it -u asha web01 bash`
   - **laptop**: `docker exec -it -u lukas laptop bash`
   - **lab-ca** (from step 8): `docker exec -it -u asha lab-ca bash`

   nginx configs are switched with `sudo cp ~/configs/allcsvideos-vN.conf /etc/nginx/sites-available/allcsvideos` on web-01.

2. The hook: plain HTTP is a postcard. On **web-01** start a capture, on the **laptop** log in (the password is fake), then Ctrl-C:
   ```bash
   sudo tcpdump -i eth0 -A -n -l 'host 10.0.44.50 and tcp port 80' | grep -E 'POST|password|Cookie'
   ```
   ```bash
   curl -s -d 'user=lukas&password=demo-password-123' http://www.allcsvideos.test/api/login
   ```
   ```
   ...HTTP: POST /api/login HTTP/1.1
   user=lukas&password=demo-password-123
   Set-Cookie: session=lab-session-7f3a9c; Path=/; HttpOnly
   ```

3. nginx as a reverse proxy. On **web-01**:
   ```bash
   cat /etc/nginx/sites-available/allcsvideos
   sudo nginx -t
   sudo nginx -s reload
   ```
   On the **laptop**:
   ```bash
   curl -v http://www.allcsvideos.test/api/health
   curl -I http://www.allcsvideos.test/
   for p in / /api/health /api/nope /api/me; do curl -s -o /dev/null -w "%{http_code}  $p\n" http://www.allcsvideos.test$p; done
   ```
   ```
   > GET /api/health HTTP/1.1
   > Host: www.allcsvideos.test
   ...
   < HTTP/1.1 200 OK
   < Server: nginx/1.24.0 (Ubuntu)
   < Content-Type: application/json
   < Content-Length: 53
   {"status": "ok", "service": "api", "host": "api-01"}
   ...
   200  /
   200  /api/health
   404  /api/nope
   401  /api/me
   ```

4. Proxy headers. On the **laptop**: `curl -s http://www.allcsvideos.test/api/whoami` shows
   `{"peer": "10.0.44.10", "host": "api", "x_forwarded_for": null, ...}`: the API sees nginx, not Lukas. On **web-01**:
   ```bash
   sudo cp ~/configs/allcsvideos-v2.conf /etc/nginx/sites-available/allcsvideos
   grep -n proxy_set_header /etc/nginx/sites-available/allcsvideos
   sudo nginx -t && sudo nginx -s reload
   ```
   Again on the **laptop**: `"host": "www.allcsvideos.test", "x_forwarded_for": "10.0.44.50", "x_forwarded_proto": "http"`.

5. Keep-alive and cookies (**laptop**):
   ```bash
   curl -v http://www.allcsvideos.test/api/health http://www.allcsvideos.test/api/health 2>&1 | grep -E '^\* (Connected|Re-using)|^< HTTP'
   curl -s -c jar.txt -d 'user=lukas&password=demo-password-123' http://www.allcsvideos.test/api/login
   curl -s http://www.allcsvideos.test/api/me
   curl -s -b jar.txt http://www.allcsvideos.test/api/me
   ```
   `Re-using existing connection`; then `{"error": "not logged in"}` without the cookie and `{"user": "lukas", "courses": 3}` with it.

6. A 502 (staged). Stop the API from your own computer, check from the **laptop**, read nginx's error log on **web-01**, then start the API again:
   ```bash
   docker exec api01 pkill -f api.py
   ```
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" http://www.allcsvideos.test/api/health      # laptop: 502
   ```
   ```bash
   sudo tail -n 1 /var/log/nginx/error.log      # web-01: connect() failed (111: Connection refused) while connecting to upstream ... 10.0.44.21:8080
   ```
   ```bash
   docker exec -d api01 sh -c 'python3 -u /srv/api.py >> /var/log/api.log 2>&1'
   ```
   The laptop's curl now prints `200` again.

7. What anyone on the path sees. On **web-01** capture only packets that carry data, on the **laptop** open the account page, then Ctrl-C:
   ```bash
   sudo tcpdump -i eth0 -A -n -q 'host 10.0.44.50 and tcp port 80 and tcp[tcpflags] & tcp-push != 0'
   ```
   ```bash
   curl -s -b jar.txt http://www.allcsvideos.test/api/me
   ```
   The request (`GET /api/me`, `Cookie: session=lab-session-7f3a9c`) and the response (`{"user": "lukas", "courses": 3}`) are readable.

8. Build a private PKI. On **lab-ca**, the root and the intermediate:
   ```bash
   cd ~/pki
   openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out root.key
   openssl req -x509 -new -key root.key -days 3650 -subj "/O=allcsvideos lab/CN=allcsvideos Lab Root CA" -out root.crt
   ls
   openssl x509 -in root.crt -noout -subject -issuer -ext basicConstraints
   openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out int.key
   openssl req -new -key int.key -subj "/O=allcsvideos lab/CN=allcsvideos Lab Intermediate CA" -out int.csr
   cat int.ext
   openssl x509 -req -in int.csr -CA root.crt -CAkey root.key -days 1825 -extfile int.ext -out int.crt
   ```
   The root's subject and issuer are the same (self-signed) and it has `CA:TRUE`.

9. The server key is made **on web-01** and never leaves it. On **web-01**:
   ```bash
   mkdir -p ~/tls && cd ~/tls
   openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out www.key
   openssl req -new -key www.key -subj "/CN=www.allcsvideos.test" -out www.csr
   ls -l
   ```
   `www.key` is `-rw-------` (only asha). Send only the CSR to the CA (from your own computer):
   ```bash
   bash lab/pass.sh web01:/home/asha/tls/www.csr lab-ca:/home/asha/pki/www.csr
   ```
   On **lab-ca**, sign it for 90 days and build the full chain:
   ```bash
   cat www.ext
   openssl x509 -req -in www.csr -CA int.crt -CAkey int.key -days 90 -extfile www.ext -out www.crt
   cat www.crt int.crt > fullchain.crt
   openssl verify -CAfile root.crt -untrusted int.crt www.crt
   openssl x509 -in www.crt -noout -text
   ```
   `www.crt: OK`. The text shows the intermediate as issuer, 90 days of validity, a 256-bit EC key, `CA:FALSE`,
   `TLS Web Server Authentication` and the SANs `www.allcsvideos.test, allcsvideos.test`.

10. Install it in nginx (with the staged mistake). From your own computer:
    ```bash
    bash lab/pass.sh lab-ca:/home/asha/pki/www.crt web01:/home/asha/tls/www.crt
    bash lab/pass.sh lab-ca:/home/asha/pki/fullchain.crt web01:/home/asha/tls/fullchain.crt
    bash lab/pass.sh lab-ca:/home/asha/pki/root.crt laptop:/home/lukas/allcsvideos-lab-root.crt
    ```
    On **web-01** (`v3` points `ssl_certificate` at `www.crt` alone):
    ```bash
    sudo install -d -m 755 /etc/nginx/tls
    sudo install -m 644 www.crt fullchain.crt /etc/nginx/tls/
    sudo install -m 600 www.key /etc/nginx/tls/
    ls -l /etc/nginx/tls
    sudo cp ~/configs/allcsvideos-v3.conf /etc/nginx/sites-available/allcsvideos
    sudo nginx -t && sudo nginx -s reload
    sudo ss -tlnp | grep nginx
    ```
    nginx now listens on 443 and 80.

11. Test from the **laptop**:
    ```bash
    curl https://www.allcsvideos.test/api/health
    curl --cacert allcsvideos-lab-root.crt https://www.allcsvideos.test/api/health
    openssl s_client -connect www.allcsvideos.test:443 -servername www.allcsvideos.test -CAfile allcsvideos-lab-root.crt -showcerts </dev/null
    ```
    Both curls fail with `curl: (60) SSL certificate problem: unable to get local issuer certificate`. s_client shows why:
    ```
    Certificate chain
     0 s:CN = www.allcsvideos.test
       i:O = allcsvideos lab, CN = allcsvideos Lab Intermediate CA
    ...
    Verify return code: 21 (unable to verify the first certificate)
    ```
    Only one certificate was sent: the intermediate is missing.

12. The fix. On **web-01**:
    ```bash
    sudo cp ~/configs/allcsvideos-v3b.conf /etc/nginx/sites-available/allcsvideos
    grep -n "ssl_certificate " /etc/nginx/sites-available/allcsvideos
    sudo nginx -t && sudo nginx -s reload
    ```
    On the **laptop**, repeat the `--cacert` curl (now `{"status": "ok", ...}`) and the s_client command: depth 2, 1 and 0 verify,
    the chain lists certificates `0` and `1`, `Verify return code: 0 (ok)`, `TLSv1.3`, `TLS_AES_256_GCM_SHA384`, `X25519`.
    Then trust the lab root system-wide (on this lab laptop only):
    ```bash
    sudo cp allcsvideos-lab-root.crt /usr/local/share/ca-certificates/
    sudo update-ca-certificates
    curl https://www.allcsvideos.test/api/health
    ```
    `1 added, 0 removed; done.` and plain curl works.

13. Watch the handshake and HTTP/2 (**laptop**):
    ```bash
    curl --http2 -v https://www.allcsvideos.test/api/health
    curl --http1.1 -sI https://www.allcsvideos.test/ | head -n 1
    curl --http2 -sI https://www.allcsvideos.test/ | head -n 1
    ```
    ```
    * ALPN: curl offers h2,http/1.1
    * TLSv1.3 (OUT), TLS handshake, Client hello (1):
    * TLSv1.3 (IN), TLS handshake, Server hello (2):
    * TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
    * TLSv1.3 (IN), TLS handshake, Certificate (11):
    * TLSv1.3 (IN), TLS handshake, CERT verify (15):
    * TLSv1.3 (IN), TLS handshake, Finished (20):
    * SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519 / id-ecPublicKey
    * ALPN: server accepted h2
    *  subjectAltName: host "www.allcsvideos.test" matched cert's "www.allcsvideos.test"
    *  SSL certificate verify ok.
    ...
    HTTP/1.1 200 OK
    HTTP/2 200
    ```
    Sniff again, now on 443. **web-01**, then the **laptop**, then Ctrl-C:
    ```bash
    sudo tcpdump -i eth0 -A -n -q 'host 10.0.44.50 and tcp port 443 and tcp[tcpflags] & tcp-push != 0'
    ```
    ```bash
    curl -s -b jar.txt https://www.allcsvideos.test/api/me
    ```
    Only the server name (SNI) and the ALPN list `h2.http/1.1` in the client hello are readable; everything else is noise.
    (nginx 1.25.1+ uses a separate `http2 on;` directive; Ubuntu 24.04 ships 1.24, so the configs use `listen 443 ssl http2`.)

14. Redirect to HTTPS and HSTS. On **web-01**:
    ```bash
    sudo cp ~/configs/allcsvideos-v4.conf /etc/nginx/sites-available/allcsvideos
    sed -n 4,15p /etc/nginx/sites-available/allcsvideos
    grep -n Strict /etc/nginx/sites-available/allcsvideos
    sudo nginx -t && sudo nginx -s reload
    ```
    On the **laptop**:
    ```bash
    curl -I http://www.allcsvideos.test/api/health
    curl -sI https://www.allcsvideos.test/ | grep -i strict
    curl -s https://www.allcsvideos.test/api/whoami
    ```
    `HTTP/1.1 301 Moved Permanently`, `Location: https://...`, `strict-transport-security: max-age=300`, and `"x_forwarded_proto": "https"`.

15. Let's Encrypt, offline, with Pebble. On **web-01**:
    ```bash
    cd ~
    curl -s --cacert /etc/pebble/pebble.minica.pem https://pebble:14000/dir; echo
    sudo REQUESTS_CA_BUNDLE=/etc/pebble/pebble.minica.pem certbot certonly --webroot -w /var/www/acme -d www.allcsvideos.test -d allcsvideos.test --server https://pebble:14000/dir -m asha@example.com --agree-tos --no-eff-email
    sudo grep acme-challenge /var/log/nginx/access.log | tail -n 3
    sudo ls -l /etc/letsencrypt/live/www.allcsvideos.test/
    sudo openssl x509 -in /etc/letsencrypt/live/www.allcsvideos.test/cert.pem -noout -subject -issuer -dates -ext subjectAltName
    ```
    ```
    Account registered.
    Requesting a certificate for www.allcsvideos.test and allcsvideos.test
    Successfully received certificate.
    Certificate is saved at: /etc/letsencrypt/live/www.allcsvideos.test/fullchain.pem
    ...
    10.0.44.100 - - [...] "GET /.well-known/acme-challenge/... HTTP/1.1" 200 87 "-" "LetsEncrypt-Pebble-VA (linux; arm64)"
    ...
    subject=
    issuer=CN = Pebble Intermediate CA 413f74
    X509v3 Subject Alternative Name: critical
        DNS:www.allcsvideos.test, DNS:allcsvideos.test
    ```
    `REQUESTS_CA_BUNDLE` only tells certbot to trust Pebble's test HTTPS certificate. Lab only. (Your Pebble CA names end in different random hex.)

16. Switch nginx to it, and forget to reload (staged). On **web-01**:
    ```bash
    sudo cp ~/configs/allcsvideos-v5.conf /etc/nginx/sites-available/allcsvideos
    grep -n "ssl_certificate" /etc/nginx/sites-available/allcsvideos
    sudo nginx -t
    ```
    On the **laptop**:
    ```bash
    openssl s_client -connect www.allcsvideos.test:443 -servername www.allcsvideos.test </dev/null 2>/dev/null | grep -E "^(subject|issuer)="
    ```
    Still the lab intermediate: nginx reads certificates only on start or reload. On **web-01**, reload and fetch Pebble's (throwaway) root:
    ```bash
    sudo nginx -s reload
    curl -s --cacert /etc/pebble/pebble.minica.pem https://pebble:15000/roots/0 -o pebble-root.pem
    openssl x509 -in pebble-root.pem -noout -subject
    ```
    From your own computer: `bash lab/pass.sh web01:/home/asha/pebble-root.pem laptop:/home/lukas/pebble-root.pem`. Then on the **laptop**:
    ```bash
    openssl s_client -connect www.allcsvideos.test:443 -servername www.allcsvideos.test </dev/null 2>/dev/null | grep -E "^(subject|issuer)="
    curl -sS https://www.allcsvideos.test/api/health
    curl -sS --cacert pebble-root.pem https://www.allcsvideos.test/api/health
    ```
    Issuer `Pebble Intermediate CA ...`; plain curl fails (nobody trusts Pebble's root), with `--cacert pebble-root.pem` it works.

17. An expired certificate (staged). On **lab-ca**, a certificate that expires the moment it's made:
    ```bash
    openssl x509 -req -in www.csr -CA int.crt -CAkey int.key -days 0 -extfile www.ext -out www-expired.crt
    openssl x509 -in www-expired.crt -noout -dates
    cat www-expired.crt int.crt > fullchain-expired.crt
    ```
    From your own computer: `bash lab/pass.sh lab-ca:/home/asha/pki/fullchain-expired.crt web01:/home/asha/tls/fullchain-expired.crt`.
    On **web-01**, go back to the lab-PKI config (v4) and install the expired chain:
    ```bash
    sudo cp ~/configs/allcsvideos-v4.conf /etc/nginx/sites-available/allcsvideos
    cd ~/tls
    sudo install -m 644 fullchain-expired.crt /etc/nginx/tls/fullchain.crt
    sudo nginx -t && sudo nginx -s reload
    ```
    nginx never checks the dates. Clients do (**laptop**):
    ```bash
    curl https://www.allcsvideos.test/api/health
    openssl s_client -connect www.allcsvideos.test:443 -servername www.allcsvideos.test </dev/null 2>/dev/null | openssl x509 -noout -enddate -checkend 0
    ```
    `curl: (60) SSL certificate problem: certificate has expired` and `Certificate will expire`. Monitor it on **web-01**:
    ```bash
    cert-check www.allcsvideos.test; echo "exit code $?"
    ```
    `CRIT    cert www.allcsvideos.test       EXPIRED (...)` and `exit code 2`. Put the Let's Encrypt certificate back:
    ```bash
    cd ~
    sudo cp ~/configs/allcsvideos-v5.conf /etc/nginx/sites-available/allcsvideos
    sudo nginx -t && sudo nginx -s reload
    cert-check www.allcsvideos.test; echo "exit code $?"
    ```
    `OK      cert www.allcsvideos.test       89 days left (...)` and `exit code 0`.

18. Automatic renewal. On **web-01**:
    ```bash
    sudo certbot certificates
    grep -v "^#" /etc/cron.d/certbot
    cat /usr/lib/systemd/system/certbot.timer
    sudo cat /etc/letsencrypt/renewal/www.allcsvideos.test.conf
    sudo install -m 755 ~/configs/reload-nginx /etc/letsencrypt/renewal-hooks/deploy/reload-nginx
    sudo cat /etc/letsencrypt/renewal-hooks/deploy/reload-nginx
    ```
    The timer runs twice a day (`OnCalendar=*-*-* 00,12:00:00`, `RandomizedDelaySec=43200`); the renewal file says
    `renew_before_expiry = 30 days`, `authenticator = webroot`. Test it:
    ```bash
    sudo REQUESTS_CA_BUNDLE=/etc/pebble/pebble.minica.pem certbot renew --dry-run
    sudo REQUESTS_CA_BUNDLE=/etc/pebble/pebble.minica.pem certbot renew --dry-run --server https://pebble:14000/dir
    sudo REQUESTS_CA_BUNDLE=/etc/pebble/pebble.minica.pem certbot renew
    sudo REQUESTS_CA_BUNDLE=/etc/pebble/pebble.minica.pem certbot renew --force-renewal
    ```
    The first dry run fails (`Failed to resolve 'acme-staging-v02.api.letsencrypt.org'`): dry runs always use Let's Encrypt's staging
    server, and this lab is offline. With `--server` pointing at Pebble: `all simulated renewals succeeded`. A plain `renew` says
    `Certificate not yet due for renewal`. The forced renewal shows `Hook 'deploy-hook' ran with error output: ... signal process started`
    (that's nginx confirming the reload) and `all renewals succeeded`. On the **laptop**, a new serial and new dates:
    ```bash
    openssl s_client -connect www.allcsvideos.test:443 -servername www.allcsvideos.test </dev/null 2>/dev/null | openssl x509 -noout -serial -dates
    ```

19. Two more pitfalls (**laptop**):
    ```bash
    curl -sS --cacert pebble-root.pem https://10.0.44.10/api/health
    curl -sS --cacert pebble-root.pem https://www.allcsvideos.test/ | grep -n "http://"
    ```
    `SSL: no alternative certificate subject name matches target host name '10.0.44.10'`, and line 3 loads a script over plain
    `http://` (mixed content, which browsers block). Fix the page (from your own computer) and check again (**laptop**):
    ```bash
    docker exec store01 sed -i 's#http://www.allcsvideos.test/static/player.js#/static/player.js#' /srv/store/index.html
    ```
    ```bash
    curl -sS --cacert pebble-root.pem https://www.allcsvideos.test/ | grep -n "player.js"
    ```
    `3:<script src="/static/player.js"></script>`

### In production
- The real ACME directory is `https://acme-v02.api.letsencrypt.org/directory`; its root, ISRG Root X1, is already in every trust store.
- The name must resolve to your server in public DNS and port 80 must be reachable for HTTP-01; otherwise (or for wildcards) use DNS-01.
- Rate limits (as of August 2026): 50 certificates per registered domain per 7 days, 5 for the exact same set of names, 5 failed validations per name per hour. Test against the staging endpoint first.
- Lifetimes are shrinking: Let's Encrypt plans 64-day certificates from February 2027 and 45 days from February 2028.
- Raise HSTS `max-age` (e.g. to a year) only once HTTPS is solid everywhere; `includeSubDomains` and `preload` are even harder to undo.

## Common mistakes
- **Missing intermediate.** `ssl_certificate` must be the full chain. It can work in your browser and fail for curl, Java and phones. `s_client -showcerts` should list more than one certificate.
- **Wrong name.** The name you connect with must be in the SANs; list every name you serve (bare domain and `www`).
- **Expired certificates.** Automate renewal, test it with a dry run, and monitor expiry from outside, because a timer can fail quietly.
- **Mixed content.** An HTTPS page loading `http://` scripts breaks; use relative paths or `https://`.
- **Forgetting to reload.** New certificate files mean nothing until nginx reloads. Use a deploy hook, and check what is *served*, not what is on disk.
- **Missing proxy headers.** Without `Host` and `X-Forwarded-*`, the app sees the proxy's address and the upstream's name.

## Clean up
```bash
bash lab/down.sh
```

## Next
[M04-L05 · The Troubleshooting Toolbox](../m04-l05-the-troubleshooting-toolbox/)
