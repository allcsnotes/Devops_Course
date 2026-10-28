# M04-L02 · DNS in Practice
> Video: Module 4, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- How one lookup really travels: stub resolver -> recursive resolver -> root -> TLD -> authoritative server, with caching at every step.
- How Linux decides where a name comes from (`nsswitch.conf`, `/etc/hosts`, `resolv.conf`), and why `dig` and your app can disagree.
- How to read every line `dig` prints, and the record types A, AAAA, CNAME, MX, TXT, NS, SOA, PTR, SRV and CAA.
- Why "it's always DNS": the TTL is a promise you can't take back. Replay the outage, then do a server move the safe way.
- Negative caching, the missing-trailing-dot bug, and Docker's embedded DNS server.

## Before you start
- Docker Desktop running. The lab is seven Ubuntu 24.04 containers running BIND 9 from Ubuntu's own packages
  (the video used BIND 9.18.39; your apt install may print a slightly newer 9.18.x).
- Basic IP and `/24` knowledge from [M04-L01](../m04-l01-ip-addresses-subnets-and-cidr/). If that lab is still running, stop it first (`bash ../m04-l01-ip-addresses-subnets-and-cidr/lab/down.sh`).
- Everything uses the `.test` domain, reserved by RFC 2606, so nothing in the lab can collide with a real domain. No internet is needed, except for the optional public `+trace` in step 8.

## Files in this folder
| File | What it is |
|------|------------|
| `lab/Dockerfile` | Lab image: Ubuntu 24.04 + `bind9`, `bind9-utils`, `bind9-dnsutils` (dig, host, nslookup), `curl`, `python3`, `nano` |
| `lab/up.sh` | Creates the `dnslab` network and the seven machines, copies in the configs and starts BIND |
| `lab/reset-for-playbook.sh` | Puts the lab back to "before the move" for the safe-migration playbook (step 10) |
| `lab/down.sh` | Removes everything the lab created |
| `lab/config/root/` | Lab root server: `named.conf` and the root zone `db.root` |
| `lab/config/tld/` | Lab `.test` TLD server: delegates `allcsvideos.test` to ns1 |
| `lab/config/ns1/` | The authoritative server: `named.conf.options` (recursion no), `named.conf.local`, zone `db.allcsvideos.test`, reverse zone `db.10.0.53` |
| `lab/config/resolver/` | The recursive resolver: `named.conf.options` (recursion only for the lab network) and the lab `root.hints` |
| `lab/config/named.conf.logging` | Sends BIND's log to `/var/log/named/named.log` |
| `lab/config/api/` | The `/health` answers of the two API servers |

The lab network `10.0.53.0/24`:

| Machine | Address | Role |
|---------|---------|------|
| root-ns | `.2` | lab root server |
| tld-ns | `.3` | lab TLD server for `.test` |
| ns1 | `.10` | authoritative for `allcsvideos.test` |
| resolver | `.53` | recursive caching resolver |
| web-01 (`web01`) | `.11` | the storefront, our client |
| api-01 (`api01`) | `.21` | old API server (port 8080) |
| api-02 (`api02`) | `.22` | new API server (port 8080) |

## Follow along

1. Start the lab, from this folder:
   ```bash
   bash lab/up.sh
   ```
   Open a shell on a machine with `docker exec -it -u asha <name> bash` (`web01`, `ns1`, `resolver`, `api01`).
   Use one terminal tab per machine; the prompt (`asha@ns1`, `asha@web-01`...) tells you where you are.

2. Look at ns1, the authoritative server (on **ns1**):
   ```bash
   cat /etc/bind/named.conf.local
   cat /etc/bind/named.conf.options
   cat /etc/bind/zones/db.allcsvideos.test
   ```
   Two zones of type `primary`; `recursion no`; the zone's `$TTL 3600` default and the one line with its own TTL:
   `api   86400 IN A      10.0.53.21`. Before loading any change, check it:
   ```bash
   sudo named-checkconf
   sudo named-checkzone allcsvideos.test /etc/bind/zones/db.allcsvideos.test
   sudo rndc reload
   sudo tail -n 4 /var/log/named/named.log
   ```
   You should see:
   ```
   zone allcsvideos.test/IN: loaded serial 2026102001
   OK
   server reload successful
   ... all zones loaded
   ... running
   ```

3. Look at the resolver (on **resolver**):
   ```bash
   cat /etc/bind/named.conf.options
   grep -v '^;' /usr/share/dns/root.hints.orig | head -6
   grep -c ' A ' /usr/share/dns/root.hints.orig
   cat /usr/share/dns/root.hints
   ```
   `recursion yes` but only for `10.0.53.0/24` (never run an open resolver). Ubuntu's real hints list 13 root servers
   (`13`); the lab version lists only `root-ns.test` at `10.0.53.2`.

4. The client side (on **web01**):
   ```bash
   grep hosts /etc/nsswitch.conf
   cat /etc/hosts
   cat /etc/resolv.conf
   getent hosts web-01
   getent hosts api
   getent hosts nope.allcsvideos.test; echo "exit code $?"
   ```
   You should see:
   ```
   hosts:          files dns
   nameserver 10.0.53.53
   search allcsvideos.test
   10.0.53.11      web-01
   10.0.53.21      api.allcsvideos.test
   exit code 2
   ```
   `files` (= `/etc/hosts`) comes before `dns`. `getent` asks the way programs do; `dig` talks DNS directly and never reads `/etc/hosts`.

5. Read `dig`. Empty the resolver's cache first (on **resolver**), then dig twice (on **web01**), a few seconds apart:
   ```bash
   # on resolver
   sudo rndc flush
   ```
   ```bash
   # on web01
   dig api.allcsvideos.test
   dig api.allcsvideos.test
   ```
   You should see (first run, then the second):
   ```
   ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 18677
   ;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
   ;; ANSWER SECTION:
   api.allcsvideos.test.   86400   IN      A       10.0.53.21
   ;; Query time: 13 msec
   ;; SERVER: 10.0.53.53#53(10.0.53.53) (UDP)
   ...
   api.allcsvideos.test.   86392   IN      A       10.0.53.21
   ;; Query time: 0 msec
   ```
   The second answer came from the cache, and the TTL is counting down. Now ask ns1 directly, and try the short forms:
   ```bash
   dig @10.0.53.10 api.allcsvideos.test
   dig +short api.allcsvideos.test
   dig +noall +answer api.allcsvideos.test
   host api.allcsvideos.test
   nslookup api
   dig +short api
   dig +short +search api
   ```
   From ns1 you get `flags: qr aa rd`, `WARNING: recursion requested but not available` and always the full `86400`.
   `dig +short api` prints nothing, because dig ignores the `search` line; `+search` fixes that.

6. Every record type (on **web01**):
   ```bash
   dig +noall +answer allcsvideos.test A
   dig +noall +answer allcsvideos.test AAAA
   dig +noall +answer www.allcsvideos.test
   dig +short MX allcsvideos.test
   dig +short TXT allcsvideos.test
   dig +short NS allcsvideos.test
   dig +noall +answer SOA allcsvideos.test
   dig +short -x 10.0.53.21
   dig +noall +answer -x 10.0.53.22
   dig +short SRV _postgresql._tcp.allcsvideos.test
   dig +short CAA allcsvideos.test
   ```
   Some of what you should see:
   ```
   www.allcsvideos.test.   3600    IN      CNAME   allcsvideos.test.
   allcsvideos.test.       3598    IN      A       10.0.53.11
   10 mail.allcsvideos.test.
   "v=spf1 mx -all"
   allcsvideos.test. 3600 IN SOA ns1.allcsvideos.test. hostmaster.allcsvideos.test. 2026102001 3600 600 604800 60
   api-01.allcsvideos.test.
   22.53.0.10.in-addr.arpa. 3600   IN      PTR     api-02.allcsvideos.test.
   0 0 5432 db-01.allcsvideos.test.
   0 issue "letsencrypt.org"
   ```
   (The site-verification TXT value is a fake demo value.)

7. A CNAME can't sit at the apex. On **ns1**, make a copy of the zone with the apex `A` record replaced by a CNAME, and check it:
   ```bash
   sed '9s/.*/    IN CNAME  lb.allcsvideos.test./' /etc/bind/zones/db.allcsvideos.test > /tmp/db.apex-test
   sed -n 8,9p /tmp/db.apex-test
   named-checkzone allcsvideos.test /tmp/db.apex-test
   rm /tmp/db.apex-test
   ```
   You should see:
   ```
   dns_master_load: /tmp/db.apex-test:14: allcsvideos.test: CNAME and other data
   zone allcsvideos.test/IN: not loaded due to errors.
   ```

8. Follow the whole path with `+trace` (on **web01**):
   ```bash
   dig +trace api-02.allcsvideos.test
   ```
   ```
   .                       86324   IN      NS      root-ns.test.
   test.                   86400   IN      NS      tld-ns.test.
   ;; Received 121 bytes from 10.0.53.2#53(root-ns.test) in 1 ms
   allcsvideos.test.       86400   IN      NS      ns1.allcsvideos.test.
   ;; Received 114 bytes from 10.0.53.3#53(tld-ns.test) in 0 ms
   api-02.allcsvideos.test. 3600   IN      A       10.0.53.22
   ;; Received 130 bytes from 10.0.53.10#53(ns1.allcsvideos.test) in 0 ms
   ```
   Optional, the same on the real internet (a public, read-only lookup), from your laptop:
   ```bash
   docker run --rm dnslab:m04l02 dig +trace +nodnssec example.com
   ```
   You'll see the 13 root servers `a` to `m`, then the `com` servers, then example.com's own name servers, and finally the addresses.

9. Replay the Friday outage. On **web01**, call the API:
   ```bash
   curl -s http://api.allcsvideos.test:8080/health
   ```
   `{"status":"ok","server":"api-01"}`, and the resolver now has `api` cached for a day. Move the API on **ns1**
   (two lines: the address, and the serial goes up by one):
   ```bash
   Z=/etc/bind/zones/db.allcsvideos.test
   sudo sed -i -e 's/2026102001  ; serial/2026102002  ; serial/' -e '/^api /s/10.0.53.21/10.0.53.22/' $Z
   grep -n -E 'serial|^api ' $Z
   sudo named-checkzone allcsvideos.test $Z
   sudo rndc reload allcsvideos.test
   ```
   ```
   3:            2026102002  ; serial
   19:api   86400 IN A      10.0.53.22
   zone reload queued
   ```
   Check ns1 directly (on **web01**), then shut api-01 down (on your **laptop**), then call the API again (on **web01**):
   ```bash
   dig @10.0.53.10 +short api.allcsvideos.test        # web01: 10.0.53.22
   ```
   ```bash
   docker stop api01                                   # laptop
   ```
   ```bash
   curl -sS --connect-timeout 5 http://api.allcsvideos.test:8080/health
   dig +noall +answer api.allcsvideos.test
   dig @10.0.53.10 +noall +answer api.allcsvideos.test
   ```
   ```
   curl: (7) Failed to connect to api.allcsvideos.test port 8080 after 3096 ms: Couldn't connect to server
   api.allcsvideos.test.   86209   IN      A       10.0.53.21
   api.allcsvideos.test.   86400   IN      A       10.0.53.22
   ```
   The resolver still holds the old answer. Look inside its cache, then stop the bleeding (on **resolver**):
   ```bash
   sudo rndc dumpdb -cache
   sudo grep -A3 '^api\.allcsvideos' /var/cache/bind/named_dump.db
   sudo rndc flushname api.allcsvideos.test
   ```
   And on **web01**:
   ```bash
   dig +noall +answer api.allcsvideos.test
   curl -sS --connect-timeout 5 http://api.allcsvideos.test:8080/health
   ```
   `10.0.53.22` with a fresh `86400`, and `api-02` answers. You can only flush resolvers you run; everyone else's waits out the TTL.

10. Now the safe way. Reset the lab to "before the move" (on your **laptop**):
    ```bash
    bash lab/reset-for-playbook.sh
    ```
    This restarts api-01, points `api` back at `.21` with the one-day TTL (serial `2026102003`), primes the resolver's cache,
    and starts a background storefront on web01 calling the API every 2 seconds.

    **Step 1, a few days before: lower the TTL** (on **ns1**):
    ```bash
    Z=/etc/bind/zones/db.allcsvideos.test
    sudo sed -i -e 's/2026102003  ; serial/2026102004  ; serial/' -e 's/^api   86400 IN/api   30    IN/' $Z
    grep -n -E 'serial|^api ' $Z
    sudo named-checkzone allcsvideos.test $Z
    sudo rndc reload allcsvideos.test
    ```
    On **web01**:
    ```bash
    dig @10.0.53.10 +noall +answer api.allcsvideos.test     # 30
    dig +noall +answer api.allcsvideos.test                  # still ~86382: cached under the old promise
    ```
    **Step 2: wait at least one old TTL (a full day).** As a stand-in for that day passing, flush the name (on **resolver**),
    then check again (on **web01**):
    ```bash
    sudo rndc flushname api.allcsvideos.test                 # resolver
    ```
    ```bash
    dig +noall +answer api.allcsvideos.test                  # web01: TTL 29 or 30
    ```
    **Step 3: make the change**, keeping api-01 running (on **ns1**):
    ```bash
    sudo sed -i -e 's/2026102004  ; serial/2026102005  ; serial/' -e '/^api /s/10.0.53.21/10.0.53.22/' $Z
    grep -n -E 'serial|^api ' $Z
    sudo named-checkzone allcsvideos.test $Z
    sudo rndc reload allcsvideos.test
    ```
    Watch the switch on **web01**:
    ```bash
    for i in 1 2 3 4 5; do
    dig +noall +answer api.allcsvideos.test
    curl -s api.allcsvideos.test:8080/health
    sleep 10; done
    ```
    ```
    api.allcsvideos.test.   22      IN      A       10.0.53.21
    {"status":"ok","server":"api-01"}
    api.allcsvideos.test.   12      IN      A       10.0.53.21
    {"status":"ok","server":"api-01"}
    api.allcsvideos.test.   30      IN      A       10.0.53.22
    {"status":"ok","server":"api-02"}
    ...
    ```
    **Step 4: keep the old server until its traffic stops** (on **api01**; open a new shell there, it was restarted):
    ```bash
    tail -n 3 /var/log/api.log
    date +%T
    ```
    When the last request is well in the past, shut it down (on your **laptop**): `docker stop api01`.

    **Step 5: raise the TTL again**, here to one hour (on **ns1**), and verify (on **web01**):
    ```bash
    sudo sed -i -e 's/2026102005  ; serial/2026102006  ; serial/' -e 's/^api   30    IN/api   3600  IN/' $Z
    grep -n -E 'serial|^api ' $Z
    sudo named-checkzone allcsvideos.test $Z
    sudo rndc reload allcsvideos.test
    ```
    ```bash
    dig @10.0.53.10 +noall +answer api.allcsvideos.test     # web01: 3600 ... 10.0.53.22
    ```
    Lower, wait, change, keep the old server, raise.

11. Negative caching. On **web01**, look up a name that doesn't exist yet:
    ```bash
    dig status.allcsvideos.test
    ```
    `status: NXDOMAIN`, and in the AUTHORITY SECTION the SOA with TTL `60` (the smaller of the SOA's own TTL and its last field).
    Now add the record on **ns1**:
    ```bash
    sudo sed -i 's/2026102006  ; serial/2026102007  ; serial/' $Z
    echo 'status      IN A      10.0.53.11' | sudo tee -a $Z
    grep -n -E 'serial|^status' $Z
    sudo rndc reload allcsvideos.test
    ```
    And compare on **web01**:
    ```bash
    dig @10.0.53.10 +short status.allcsvideos.test     # 10.0.53.11
    dig +short status.allcsvideos.test                 # nothing: the resolver remembers the "no"
    for i in 1 2 3 4; do
    dig +noall +answer +authority status.allcsvideos.test
    sleep 15; done
    dig +noall +answer +authority status.allcsvideos.test
    ```
    The loop shows the cached "no" counting down (52, 36, 21, 6...), then the real answer: `status.allcsvideos.test. 3600 IN A 10.0.53.11`.

12. The missing trailing dot. On **ns1**, add an alias without the final dot:
    ```bash
    sudo sed -i 's/2026102007  ; serial/2026102008  ; serial/' $Z
    echo 'docs        IN CNAME  www.allcsvideos.test' | sudo tee -a $Z
    grep -n -E 'serial|^docs' $Z
    sudo named-checkzone allcsvideos.test $Z
    sudo rndc reload allcsvideos.test
    ```
    `named-checkzone` says `OK`. Now on **web01**: `dig docs.allcsvideos.test` returns `NXDOMAIN` with
    `docs.allcsvideos.test.  3600    IN      CNAME   www.allcsvideos.test.allcsvideos.test.` See how BIND reads it (on **ns1**):
    ```bash
    sudo named-checkzone -D allcsvideos.test $Z | grep '^docs'
    ```
    Fix it (add the dot, bump the serial) on **ns1**:
    ```bash
    sudo sed -i -e 's/2026102008  ; serial/2026102009  ; serial/' -e 's/^docs .*/docs        IN CNAME  www.allcsvideos.test./' $Z
    grep -n -E 'serial|^docs' $Z
    sudo named-checkzone allcsvideos.test $Z
    sudo rndc reload allcsvideos.test
    ```
    On **web01**, ns1 now answers the chain, but the resolver still serves the broken alias:
    ```bash
    dig @10.0.53.10 +noall +answer docs.allcsvideos.test
    dig +short docs.allcsvideos.test
    ```
    Flush it (on **resolver**: `sudo rndc flushname docs.allcsvideos.test`), then on **web01**:
    ```bash
    dig +noall +answer docs.allcsvideos.test
    ```
    ```
    docs.allcsvideos.test.  3600    IN      CNAME   www.allcsvideos.test.
    www.allcsvideos.test.   3600    IN      CNAME   allcsvideos.test.
    allcsvideos.test.       3600    IN      A       10.0.53.11
    ```

13. Docker's own DNS server. On your **laptop**:
    ```bash
    docker run --rm --network dnslab dnslab:m04l02 cat /etc/resolv.conf
    docker run --rm --network dnslab dnslab:m04l02 getent hosts ns1
    docker run --rm dnslab:m04l02 getent hosts ns1; echo "exit code $?"
    ```
    ```
    nameserver 127.0.0.11
    # ExtServers: [host(...)]
    10.0.53.10      ns1
    exit code 2
    ```
    On a user-defined network Docker's embedded DNS (`127.0.0.11`) answers container names; on the default bridge it doesn't.
    (web01's `resolv.conf` was edited by `up.sh`, which is why Docker stopped managing it and it uses the lab resolver.)

14. Pitfall: a forgotten `/etc/hosts` edit. On **web01**, pin `api` the way someone did "for a quick test" weeks ago:
    ```bash
    echo '10.0.53.21 api.allcsvideos.test' | sudo tee -a /etc/hosts
    dig +short api.allcsvideos.test
    getent hosts api.allcsvideos.test
    curl -sS --connect-timeout 5 http://api.allcsvideos.test:8080/health
    grep -n api /etc/hosts
    ```
    ```
    10.0.53.22
    10.0.53.21      api.allcsvideos.test
    curl: (28) Failed to connect to api.allcsvideos.test port 8080 after 5008 ms: Timeout was reached
    8:10.0.53.21 api.allcsvideos.test
    ```
    `dig` says `.22`, but programs read `/etc/hosts` first. Remove the line (inside a container `/etc/hosts` must be rewritten in place, so `sed -i` won't work there):
    ```bash
    grep -v 'api.allcsvideos.test' /etc/hosts > /tmp/hosts && sudo tee /etc/hosts < /tmp/hosts > /dev/null
    grep -c api /etc/hosts
    getent hosts api.allcsvideos.test
    curl -sS --connect-timeout 5 http://api.allcsvideos.test:8080/health
    ```
    `0`, `10.0.53.22`, and `{"status":"ok","server":"api-02"}`.

## Common mistakes
- **A forgotten `/etc/hosts` entry.** When `dig` and your app disagree, check `/etc/hosts` first.
- **Caches you don't control.** Resolvers, systemd-resolved, browsers and runtimes like Java all keep answers, some longer than the TTL. Lower TTLs before a change, keep the old server running, and compare the resolver with the authoritative server (`dig @ns`).
- **Negative caching.** A lookup before a name exists caches the "no" for the SOA's negative TTL. Create records before anything asks for them.
- **CNAME chains and apex CNAMEs.** `docs -> www -> apex` is three records and a change only lands as each link expires. Point aliases straight at the final name. Never put a CNAME at the apex; use your provider's ALIAS/ANAME (Route 53: alias record).
- **Zone file classics.** A missing trailing dot on full names (CNAME targets, MX, NS), and a serial that wasn't bumped, so secondaries never pick up the change.
- **Never use a domain you don't own in a lab.** Use `.test`.

## Clean up
```bash
bash lab/down.sh
```

## Next
[M04-L03 · Ports, TCP and Firewalls](../m04-l03-ports-tcp-and-firewalls/)
