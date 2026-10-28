# M06-L06 · Container Networking
> Video: Module 6, Lesson 6. Watch it first, then follow along here.

## What you'll learn
- Why `localhost` inside a container means that container only, and why "connection refused" is the classic first bug.
- What a bridge network really is: a Linux bridge, a veth pair per container, NAT on the way out, DNAT for published ports.
- Why the default bridge has no DNS, and how a user-defined network gives you names and aliases through Docker's DNS at `127.0.0.11`.
- Splitting front end from back end with two networks, one of them `--internal`, and a container attached to both.
- Publishing ports safely (bound to an address), the `host` and `none` modes, and debugging with netshoot in a container's namespace.
- The pitfalls: hardcoded container IPs, published databases, and subnet clashes (fixed in `daemon.json`).

## Before you start
- Docker Desktop (the video used 4.79, engine 29.5.3) or Docker Engine on Linux, plus `curl` on your laptop.
- You should have done [M06-L01](../m06-l01-vms-vs-containers/) (namespaces, `eth0@ifNN`, the VM-view shell) and [M06-L03](../m06-l03-running-containers/) (publishing ports). Module 4 (DNS, NAT, iptables) helps with the "under the hood" part.
- Images the lesson pulls (all pinned): `postgres:18.6-alpine3.24`, `redis:8.10.2-alpine3.23`, `python:3.13.16-alpine3.23` and `nginx:1.29.8-alpine` (as bases), `nicolaka/netshoot:v0.16`, `ubuntu:24.04` (VM view), `docker:29.5.3-dind` (only for `dockerd --validate`).
- Every command uses the FAKE demo password `demo-password-123`.

## Files in this folder
| File | What it is |
|---|---|
| `api/app.py`, `api/Dockerfile` | The allcsvideos API stand-in (Python standard library only). Reads `DB_HOST`, `REDIS_HOST`; logs a real database/Redis check at start; serves `/health` and `/whoami` on port 8080 |
| `web/Dockerfile`, `web/default.conf`, `web/site/index.html` | The storefront: nginx serving a page and proxying `/api/` to `http://api:8080/` by name |
| `vmview/Dockerfile` | The VM-view lab shell (Ubuntu + `ip` + `iptables`) for looking at bridges and NAT rules on the Docker host |
| `daemon.json` | The Docker daemon settings that move Docker's address ranges (`bip`, `default-address-pools`) |

Names used below: containers `allcs-db`, `allcs-api`, `allcs-web`, ...; networks `allcs-app`, `allcs-front`, `allcs-back`; images `allcs/api:1.0`, `allcs/web:1.0`, `allcs/vmview:1.0`.

## Follow along

### 0. Build the lesson images
```bash
cd Devops_Course/docker/m06-l06-container-networking
docker build -t allcs/api:1.0 api
docker build -t allcs/web:1.0 web
docker build -t allcs/vmview:1.0 vmview
```

### 1. The hook: localhost (staged on purpose)
```bash
docker run -d --name allcs-db -e POSTGRES_PASSWORD=demo-password-123 postgres:18.6-alpine3.24
docker run -d --name allcs-api -e DB_HOST=localhost allcs/api:1.0
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter name=allcs-
docker logs allcs-api
```
```
database localhost:5432 -> ConnectionRefusedError: [Errno 111] Connection refused
```
"Maybe the port isn't open":
```bash
docker rm -f -v allcs-db
docker run -d --name allcs-db -e POSTGRES_PASSWORD=demo-password-123 -p 5432:5432 postgres:18.6-alpine3.24
docker restart allcs-api
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter name=allcs-
docker logs allcs-api
```
Still refused, even with `0.0.0.0:5432->5432/tcp`. From the host side the database answers; from inside the API it doesn't:
```bash
docker run --rm postgres:18.6-alpine3.24 pg_isready -h host.docker.internal
docker exec allcs-api nc -zv -w 3 127.0.0.1 5432 || echo "exit code $?"
```
```
host.docker.internal:5432 - accepting connections
exit code 1
```
(`host.docker.internal` works on Docker Desktop. And publishing 5432 just opened the database to anyone who can reach your laptop.)

### 2. Whose localhost?
```bash
docker exec allcs-api ip addr show lo
docker exec allcs-api hostname
```
The API's `lo` (127.0.0.1) belongs to the API container alone.

### 3. The default bridge
```bash
docker rm -f -v allcs-db
docker run -d --name allcs-db -e POSTGRES_PASSWORD=demo-password-123 postgres:18.6-alpine3.24
docker network ls
docker network inspect bridge
docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' allcs-db
docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' allcs-api
```
You should see `bridge`, `host` and `none`, the subnet `172.17.0.0/16`, gateway `172.17.0.1`, and `"com.docker.network.bridge.name": "docker0"`. In the video the database got `172.17.0.8` and the API `172.17.0.12`; yours will differ, so use your own IP below.
```bash
docker exec allcs-api nc -zv -w 3 <db-ip> 5432
docker exec allcs-api nc -zv -w 3 allcs-db 5432
docker exec allcs-api cat /etc/resolv.conf
```
```
172.17.0.8 (172.17.0.8:5432) open
nc: bad address 'allcs-db'
nameserver 192.168.65.7
```
By IP it works, by name it doesn't: the default bridge has no embedded DNS. Hardcoding the IP "works, for now":
```bash
docker rm -f allcs-api
docker run -d --name allcs-api -e DB_HOST=<db-ip> allcs/api:1.0
docker logs allcs-api
```
`database 172.17.0.8:5432 -> ok`. It works, for now; step 11 shows why it's a trap.

### 4. A user-defined network: names work
```bash
docker network create allcs-app
docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} gateway {{.Gateway}}{{end}}' allcs-app
```
Docker picks the next free subnet (`172.20.0.0/16` in the video). Recreate both containers on it:
```bash
docker rm -f -v allcs-db allcs-api
docker run -d --name allcs-db --network allcs-app -e POSTGRES_PASSWORD=demo-password-123 postgres:18.6-alpine3.24
docker run -d --name allcs-api --network allcs-app -e DB_HOST=allcs-db allcs/api:1.0
docker logs allcs-api
```
If the log says `Connection refused`, that's a real start-up race: Postgres wasn't ready yet. Restart the API a moment later:
```bash
docker restart allcs-api
docker logs allcs-api
```
```
database allcs-db:5432 -> ok
```
Look at the DNS setup:
```bash
docker exec allcs-api cat /etc/resolv.conf
docker exec allcs-api getent hosts allcs-db
docker exec allcs-api nslookup allcs-db
docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Networks}}" --filter name=allcs-
```
```
nameserver 127.0.0.11
options ndots:0
# ExtServers: [host(192.168.65.7)]
172.20.0.2        allcs-db  allcs-db
Server:		127.0.0.11
```
The database publishes nothing at all.

### 5. Aliases and round-robin DNS
```bash
docker run -d --name allcs-api1 --hostname api-1 --network allcs-app --network-alias api -e DB_HOST=allcs-db allcs/api:1.0
docker run -d --name allcs-api2 --hostname api-2 --network allcs-app --network-alias api -e DB_HOST=allcs-db allcs/api:1.0
docker run --rm --network allcs-app nicolaka/netshoot:v0.16 sh -c 'for i in 1 2 3 4; do echo $(dig +short api); done'
docker run --rm --network allcs-app nicolaka/netshoot:v0.16 sh -c "for i in 1 2 3 4 5 6 7 8; do curl -s api:8080/whoami; done"
```
`dig` returns both addresses in a shuffled order; the 8 requests split unevenly (6 to api-2, 2 to api-1 in the video). Round-robin DNS spreads load roughly; it isn't a load balancer.

Clear this part before the real layout:
```bash
docker rm -f -v allcs-db allcs-api allcs-api1 allcs-api2
docker network rm allcs-app
```

### 6. Front and back networks
```bash
docker network create --subnet 10.0.66.0/24 allcs-front
docker network create --subnet 10.0.67.0/24 --internal allcs-back

docker run -d --name allcs-db --network allcs-back --network-alias db -e POSTGRES_PASSWORD=demo-password-123 postgres:18.6-alpine3.24
docker run -d --name allcs-redis --network allcs-back --network-alias redis redis:8.10.2-alpine3.23

docker run -d --name allcs-api --network allcs-back --network-alias api -e DB_HOST=db -e REDIS_HOST=redis allcs/api:1.0
docker network connect --alias api allcs-front allcs-api

docker run -d --name allcs-web --network allcs-front -p 8080:80 allcs/web:1.0
```
(If the API's log shows a refused database on the first start, `docker restart allcs-api` as in step 4.)
```bash
curl -s localhost:8080
curl -s localhost:8080/api/health
docker logs allcs-api
```
```
<h1>allcsvideos storefront</h1>
{"api": "9c90f0987863", "db": "ok", "redis": "ok"}
GET /health 200 from 10.0.66.3
```
Who is on which network:
```bash
docker inspect -f '{{.Name}}{{range $n, $e := .NetworkSettings.Networks}}  {{$n}} {{$e.IPAddress}}{{end}}' allcs-web allcs-api allcs-db allcs-redis
docker exec allcs-api ip -4 addr
```
```
/allcs-web  allcs-front 10.0.66.3
/allcs-api  allcs-back 10.0.67.4  allcs-front 10.0.66.2
/allcs-db  allcs-back 10.0.67.2
/allcs-redis  allcs-back 10.0.67.3
11: eth0@if527: ... inet 10.0.67.4/24
12: eth1@if528: ... inet 10.0.66.2/24
```
Prove the wall:
```bash
docker exec allcs-web curl -sS --connect-timeout 3 http://api:8080/whoami
docker exec allcs-web curl -sS --connect-timeout 3 http://db:5432
docker exec allcs-web curl -sS --connect-timeout 3 http://10.0.67.2:5432
```
```
{"api": "9c90f0987863"}
curl: (6) Could not resolve host: db (Domain name not found)
curl: (28) Connection timed out after 3005 milliseconds
```
And `--internal` means no way out:
```bash
docker exec allcs-web curl -sS -o /dev/null -w "%{http_code}\n" --connect-timeout 5 https://example.com
docker exec allcs-db ip route
docker exec allcs-db wget -T 5 -q -O /dev/null https://example.com
docker exec allcs-db nc -zv -w 3 1.1.1.1 443 || echo "exit code $?"
```
```
200
10.0.67.0/24 dev eth0 scope link  src 10.0.67.2
wget: bad address 'example.com'
nc: 1.1.1.1 (1.1.1.1:443): Network unreachable
```
If `10.0.66.0/24` or `10.0.67.0/24` clashes with a network you already have, pick two other free `/24`s and use them consistently.

### 7. Under the hood (VM view)
Start the privileged lab shell in the Docker host's namespaces (on Docker Desktop, that's the Linux VM; the prompt says `docker-desktop`):
```bash
docker run -it --rm --privileged --net=host --pid=host --uts=host allcs/vmview:1.0
```
Inside it (`br-` names come from your network IDs; `docker network ls` shows them):
```bash
ip -br link show type bridge
ip link show master br-<back-id> | grep -o "^[0-9]*: veth[^:]*"
ip link show master br-<front-id> | grep -o "^[0-9]*: veth[^:]*"
iptables -t nat -S POSTROUTING 2>/dev/null | grep 10.0.6
iptables -t nat -S DOCKER 2>/dev/null | grep 8080
iptables -S DOCKER-INTERNAL 2>/dev/null
exit
```
```
-A POSTROUTING -s 10.0.66.0/24 ! -o br-d498cc8cfcf0 -j MASQUERADE
-A DOCKER -p tcp -m tcp --dport 8080 -j DNAT --to-destination 10.0.66.3:80
-A DOCKER-INTERNAL ! -s 10.0.67.0/24 -o br-5fd1a55b5fab -j DROP
-A DOCKER-INTERNAL ! -d 10.0.67.0/24 -i br-5fd1a55b5fab -j DROP
```
Match the veth numbers on each bridge with the API's `eth0@if527` / `eth1@if528`: two cables, two switches. There's no MASQUERADE rule for the internal `10.0.67.0/24`.

### 8. Publishing ports
```bash
docker ps --format "table {{.Names}}\t{{.Ports}}" --filter name=allcs-
docker port allcs-web
docker run -d --name allcs-web2 --network allcs-front -p 127.0.0.1:9080:80 -p 127.0.0.1:9443:443 allcs/web:1.0
docker port allcs-web2
curl -sS localhost:9080
curl -sS https://localhost:9443
```
Only `allcs-web` has an arrow. `allcs-web2` publishes two ports on loopback only; 9080 serves the storefront, 9443 fails (`Could not connect to server`) because nginx listens only on port 80 inside. On a Linux server, remember that published ports bypass ufw's input rules: bind to `127.0.0.1`, filter in `DOCKER-USER`, or use a cloud firewall.

### 9. `none` and `host`
```bash
docker run --rm --network none nicolaka/netshoot:v0.16 ip -br -4 addr
docker run --rm --network host nicolaka/netshoot:v0.16 ip -br -4 addr
docker run -d --name allcs-hostweb --network host -p 8090:80 nginx:1.29.8-alpine
```
`none` shows only `lo`. `host` shows the Docker host's interfaces (on Docker Desktop, the VM: `eth0 192.168.65.3/24`, `docker0`, the `br-` bridges). The last command prints `WARNING: Published ports are discarded when using host network mode`. Remove it right away:
```bash
docker rm -f allcs-hostweb
```

### 10. Debugging with netshoot in a container's namespace
```bash
docker run -it --rm --network container:allcs-api nicolaka/netshoot:v0.16
```
Inside (the prompt shows the API's hostname):
```bash
ip -br -4 addr
ss -tln
dig +noall +answer db
nc -zv db 5432
curl -s localhost:8080/health
exit
```
```
eth0@if527       UP             10.0.67.4/24
eth1@if528       UP             10.0.66.2/24
LISTEN  0  5     0.0.0.0:8080 ...
LISTEN  0  4096  127.0.0.11:41909 ...
db.			600	IN	A	10.0.67.2
Connection to db (10.0.67.2) 5432 port [tcp/postgresql] succeeded!
{"api": "9c90f0987863", "db": "ok", "redis": "ok"}
```
From the storefront's side:
```bash
docker run --rm --network container:allcs-web nicolaka/netshoot:v0.16 nc -zv -w 3 10.0.67.2 5432
docker run --rm --network container:allcs-web nicolaka/netshoot:v0.16 ip route
```
The connection times out; the route table has only its own subnet and `default via 10.0.66.1`.

### 11. Pitfalls, shown for real
Publishing a database to every interface vs loopback (staged on purpose):
```bash
docker run -d --name allcs-pubdb -e POSTGRES_PASSWORD=demo-password-123 -p 5433:5432 -p 127.0.0.1:5434:5432 postgres:18.6-alpine3.24
docker port allcs-pubdb
docker run --rm --network host nicolaka/netshoot:v0.16 ip -br -4 addr show eth0
docker run --rm postgres:18.6-alpine3.24 pg_isready -h <that eth0 address> -p 5433
docker run --rm postgres:18.6-alpine3.24 pg_isready -h <that eth0 address> -p 5434 -t 3
```
```
192.168.65.3:5433 - accepting connections
192.168.65.3:5434 - no response
```
Hardcoded IPs move. In the video this was done on the default bridge with the API from step 3 still pointing at `172.17.0.8`: stop the database, start another container (it takes the freed IP), start the database again (it gets a new IP), and the API now knocks on Redis:
```
$ docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' allcs-cache allcs-db
172.17.0.8
172.17.0.13
database 172.17.0.8:5432 -> ConnectionRefusedError: [Errno 111] Connection refused
```
To try it yourself, do it at the very end: run the Clean up section's `docker rm` line, repeat step 3 (database and hardcoded-IP API on the default bridge), then:
```bash
docker stop allcs-db
docker run -d --name allcs-cache redis:8.10.2-alpine3.23
docker start allcs-db
docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' allcs-cache allcs-db
docker restart allcs-api
docker logs allcs-api
```
(Docker may hand the database back its old IP on a quiet laptop; the video needed the stop / start-another / start order to make it move.)

Subnet clashes:
```bash
docker network create --subnet 10.0.67.128/25 allcs-clash
```
```
Error response from daemon: invalid pool request: Pool overlaps with other one on this address space
```
The fix is to move Docker's ranges. Validate `daemon.json` without touching your real daemon:
```bash
cat daemon.json
docker run --rm --entrypoint dockerd -v "$PWD/daemon.json":/etc/docker/daemon.json docker:29.5.3-dind --validate
```
```
configuration OK
```
To apply it: on Docker Desktop, paste the keys under Settings > Docker Engine; on Linux, put them in `/etc/docker/daemon.json` and restart Docker. Both affect all your containers, so only do it if you have a real clash.

## Common mistakes
1. `localhost` inside a container is the container itself. Use the other container's name on a shared network.
2. Relying on the default bridge: no DNS, so names fail and people hardcode IPs. Create a user-defined network for every app.
3. Publishing a database to `0.0.0.0`. Usually, don't publish it at all; if you must, bind to `127.0.0.1`.
4. Hardcoding container IPs: they change when containers stop and start.
5. Subnet clashes: Docker refuses overlapping networks it knows about, but it can't see an office or VPN network in the same range. Move Docker's ranges with `bip` and `default-address-pools`.

## Clean up
```bash
docker rm -f -v allcs-db allcs-api allcs-api1 allcs-api2 allcs-redis allcs-cache allcs-web allcs-web2 allcs-hostweb allcs-pubdb 2>/dev/null
docker network rm allcs-app allcs-front allcs-back 2>/dev/null
docker rmi allcs/api:1.0 allcs/web:1.0 allcs/vmview:1.0
```
The `-v` in the `docker rm` commands deletes each postgres container's anonymous volume with it (lesson 5). If you removed a postgres container without `-v`, find the leftover with `docker volume ls --filter dangling=true` and delete it by name with `docker volume rm <name>`; don't run an unfiltered `docker volume prune` on a machine with other projects.

## Next
That's the end of Docker fundamentals. Next: [M07-L01 · Small, Fast Images](../m07-l01-small-fast-images/).
