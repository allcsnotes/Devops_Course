# M04-L01 · IP Addresses, Subnets and CIDR
> Video: Module 4, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- Read an IPv4 address in binary: 32 bits, four octets, each 0-255.
- Read a CIDR prefix like `10.0.1.0/24`: network bits vs host bits, network and broadcast addresses, usable hosts (and why AWS gives you 5 fewer, not 2).
- Know the special ranges: RFC 1918 private ranges, documentation ranges, loopback, link-local, and the basics of IPv6.
- The one routing rule: same subnet, deliver directly; different subnet, send to the gateway. Prove it with `ip -br a`, `ip route`, `ip route get`, `ping` and `traceroute`.
- Find and fix a wrong prefix (`/28` instead of `/24`) on a server.
- Plan the allcsvideos VPC with `ipcalc` and a small Python checker.

## Before you start
- Docker Desktop running (the lab is six small Ubuntu 24.04 containers on three Docker networks).
- Python 3 on your laptop (for `check_plan.py`; it also runs inside any lab machine).
- Nothing from an earlier lesson is needed. The lab is a bigger version of the bastion lab from the SSH lesson.

## Files in this folder
| File | What it is |
|------|------------|
| `lab/Dockerfile` | The lab machine image: Ubuntu 24.04 + `iproute2`, `ipcalc`, `ping`, `traceroute`, `python3`, user `asha` with sudo |
| `lab/up.sh` | Builds the image and creates the networks and machines (including the staged `/28` bug on cache-01) |
| `lab/down.sh` | Removes everything `up.sh` created |
| `check_plan.py` | Checks the VPC plan: every subnet inside the VPC, no overlaps, no clash with other networks |
| `network-plan.md` | The finished allcsvideos network plan (used again in modules 10 and 11) |

The lab network:

| Network | Range | Machines |
|---------|-------|----------|
| public side | `203.0.113.0/24` (documentation range) | bastion `.10` |
| private subnet A | `10.0.1.0/24` and `2001:db8:1::/64` | router `.1`, bastion `.10`, web-01 `.11`, db-01 `.21`, cache-01 `.41` |
| private subnet B | `10.0.2.0/24` | router `.1`, web-02 `.11` |

## Follow along

1. Start the lab.
   ```bash
   bash lab/up.sh
   ```
   To open a shell on any machine, use `docker exec -it -u asha <name> bash`, where `<name>` is one of
   `web01`, `db01`, `cache01`, `web02`, `bastion`, `router`. The prompt shows the host name, e.g. `asha@web-01`.

2. The problem. From web-01, ping the new cache server:
   ```bash
   docker exec -it -u asha web01 bash
   ping -c 3 10.0.1.41
   ```
   You should see:
   ```
   3 packets transmitted, 0 received, 100% packet loss
   ```
   Now from cache-01 (type `exit` first to leave web-01):
   ```bash
   docker exec -it -u asha cache01 bash
   ping -c 3 10.0.1.21
   ```
   ```
   ping: connect: Network is unreachable
   ```
   Keep this in mind; you'll come back to it in step 8.

3. Look at web-01's addresses (on web-01):
   ```bash
   ip -br a
   ip addr show eth0
   ```
   You should see (ignore the tunnel devices that are `DOWN`; the kernel adds them):
   ```
   lo               UNKNOWN        127.0.0.1/8 ::1/128
   eth0@if200       UP             10.0.1.11/24 2001:db8:1::11/64 fe80::7863:9eff:feba:3072/64
   ...
       inet 10.0.1.11/24 brd 10.0.1.255 scope global eth0
   ```
   `brd 10.0.1.255` is the broadcast address. The `link/ether` line is the MAC address, which only matters inside the local network.

4. The bastion has a foot in both networks (on bastion):
   ```bash
   ip -br a
   ```
   ```
   eth0@if198       UP             203.0.113.10/24
   eth1@if199       UP             10.0.1.10/24 2001:db8:1::10/64 ...
   ```

5. The routing table on web-01:
   ```bash
   ip route
   ```
   ```
   default via 10.0.1.1 dev eth0
   10.0.1.0/24 dev eth0 proto kernel scope link src 10.0.1.11
   ```
   Line two: the whole `10.0.1.0/24` subnet is right here on `eth0`, deliver directly. Line one: everything else goes to the gateway, the router at `.1`.

6. Prove the rule: same subnet vs different subnet (on web-01):
   ```bash
   ip route get 10.0.1.21
   ip route get 10.0.2.11
   ping -c 2 10.0.1.21
   ping -c 2 10.0.2.11
   traceroute -n 10.0.1.21
   traceroute -n 10.0.2.11
   ```
   You should see:
   ```
   10.0.1.21 dev eth0 src 10.0.1.11 uid 1000
   10.0.2.11 via 10.0.1.1 dev eth0 src 10.0.1.11 uid 1000
   64 bytes from 10.0.1.21: icmp_seq=1 ttl=64 ...
   64 bytes from 10.0.2.11: icmp_seq=1 ttl=63 ...
    1  10.0.1.21  ...
    1  10.0.1.1  ...
    2  10.0.2.11  ...
   ```
   TTL starts at 64 on Linux and every router takes one off: `ttl=63` means exactly one router in between.

7. Look at the router, then two quick checks from web-01:
   ```bash
   # on router
   ip -br a show eth0
   ip -br a show eth1
   sysctl net.ipv4.ip_forward
   ```
   ```
   eth0@if196       UP             10.0.1.1/24 2001:db8:1::1/64 ...
   eth1@if197       UP             10.0.2.1/24
   net.ipv4.ip_forward = 1
   ```
   ```bash
   # on web-01: loopback, and db-01 over IPv6
   ping -c 1 127.0.0.1
   ping -c 1 2001:db8:1::21
   ```

8. Back to cache-01. Find the bug:
   ```bash
   ip -br a show eth0
   ip route
   ip route get 10.0.1.21
   ipcalc -nb 10.0.1.41/28
   ```
   You should see:
   ```
   eth0@if202       UP             10.0.1.41/28 2001:db8:1::41/64 ...
   10.0.1.32/28 dev eth0 proto kernel scope link src 10.0.1.41
   RTNETLINK answers: Network is unreachable
   Netmask:   255.255.255.240 = 28
   Network:   10.0.1.32/28
   HostMin:   10.0.1.33
   HostMax:   10.0.1.46
   ```
   `/28` instead of `/24`. cache-01 thinks its subnet is only `.33`-`.46`, so db-01 and web-01 are "on another street",
   and there is no default route because the gateway `.1` is outside that tiny subnet. (web-01's ping did reach cache-01,
   but cache-01 had no route to send the reply back.)

9. Fix it live (on cache-01). On a real server you would fix the netplan config instead.
   ```bash
   sudo ip addr del 10.0.1.41/28 dev eth0
   sudo ip addr add 10.0.1.41/24 dev eth0
   sudo ip route add default via 10.0.1.1
   ping -c 2 10.0.1.21
   ```
   Then from web-01:
   ```bash
   ping -c 2 10.0.1.41
   ```
   Both now show `2 packets transmitted, 2 received, 0% packet loss`.

10. Let `ipcalc` do the maths (on web-01):
    ```bash
    ipcalc -n 10.0.1.0/24
    ```
    ```
    Address:   10.0.1.0             00001010.00000000.00000001. 00000000
    Netmask:   255.255.255.0 = 24   11111111.11111111.11111111. 00000000
    ...
    HostMin:   10.0.1.1
    HostMax:   10.0.1.254
    Broadcast: 10.0.1.255
    Hosts/Net: 254                   Class A, Private Internet
    ```
    The gap in the binary column is where the network part ends. Ignore "Class A": address classes were retired in 1993.

11. Plan the allcsvideos VPC. Split `10.0.0.0/16` into `/24`s:
    ```bash
    ipcalc -nb 10.0.0.0/16 /24 | tail -n 9
    ```
    ```
    Network:   10.0.255.0/24
    ...
    Subnets:   256
    Hosts:     65024
    ```
    The plan takes six of them (app `10.0.1`/`10.0.2`, data `10.0.21`/`10.0.22`, public `10.0.101`/`10.0.102`; zone A ends in 1, zone B in 2).
    Check it on your laptop, from this folder:
    ```bash
    python3 check_plan.py
    ```
    ```
    public-a  10.0.101.0/24  inside VPC: True  usable on AWS: 251
    ...
    data-b    10.0.22.0/24   inside VPC: True  usable on AWS: 251
    office VPN             192.168.10.0/24  overlaps VPC: False
    docker default bridge  172.17.0.0/16    overlaps VPC: False
    staging VPC (copied)   10.0.0.0/16      overlaps VPC: True
    staging VPC (fixed)    10.1.0.0/16      overlaps VPC: False
    ```
    The finished plan is in [`network-plan.md`](network-plan.md).

12. Docker catches overlaps too. On your laptop, with the lab still running:
    ```bash
    docker network inspect bridge --format '{{(index .IPAM.Config 0).Subnet}}'
    docker network create --subnet 10.0.1.0/24 overlap-test
    ```
    ```
    172.17.0.0/16
    Error response from daemon: invalid pool request: Pool overlaps with other one on this address space
    ```

13. The interview question: how many hosts fit in a `/27`? Work it out (32 - 27 = 5 host bits, 2^5 = 32 addresses, 30 usable, 27 on AWS), then check (on any lab machine):
    ```bash
    ipcalc -nb 10.0.1.0/27
    ```
    ```
    Netmask:   255.255.255.224 = 27
    HostMin:   10.0.1.1
    HostMax:   10.0.1.30
    Broadcast: 10.0.1.31
    Hosts/Net: 30
    ```

## Common mistakes
- **Overlapping CIDR blocks.** AWS won't peer two VPCs whose blocks overlap, and a VPN to an office that uses your range sends traffic to the wrong place. A staging VPC copied as `10.0.0.0/16` collides with production; give it `10.1.0.0/16`.
- **Docker's default bridge is `172.17.0.0/16`.** If your office or VPN also uses 172.17, a Linux server running Docker sends that traffic to its local bridge. Move Docker's ranges with the `bip` and `default-address-pools` settings.
- **Subnets that are too small.** A `/28` leaves you 11 addresses on AWS, and load balancers, autoscaling and Kubernetes pods use them up fast. You can't resize a subnet later; you rebuild it.
- **Inventing addresses.** A random public-looking range inside your network hides its real owner from you. Stay inside RFC 1918 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) and use the documentation ranges (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`) for examples.
- **A wrong prefix on one server** (like `/28` vs `/24`) makes neighbours look like they live on another network, and can remove the default route.

## Clean up
```bash
docker network rm overlap-test 2>/dev/null   # only if step 12 somehow succeeded
bash lab/down.sh
```

## Next
[M04-L02 · DNS in Practice](../m04-l02-dns-in-practice/)
