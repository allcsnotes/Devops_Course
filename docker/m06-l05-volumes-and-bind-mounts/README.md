# M06-L05 · Volumes and Bind Mounts
> Video: Module 6, Lesson 5. Watch it first, then follow along here.

## What you'll learn
- Why a database container "loses everything" on `docker rm`, and where the data actually went (anonymous volumes and orphans).
- The three ways to keep data outside the writable layer: named volumes, bind mounts, and tmpfs mounts, and when to use each.
- `-v` versus `--mount`, and why `--mount` is clearer and safer.
- Bind-mount gotchas: typos, hiding image files, single-file mounts, file ownership, and speed on a Mac.
- Backing up a volume: a stopped-database `tar` copy versus `pg_dump`, and testing the restore.
- Sharing volumes, and deleting them safely (`volume rm`, `volume prune` with a filter).

## Before you start
- Docker Desktop (the video used 4.79, engine 29.5.3, on an Apple-silicon Mac with virtiofs file sharing) or Docker Engine on Linux.
- `curl` on your laptop.
- You should have done [M06-L02](../m06-l02-images-layers-and-registries/) (the writable layer, `docker diff`) and [M06-L03](../m06-l03-running-containers/) (`docker run`, `-p`).
- Images the lesson pulls (all pinned): `postgres:18.4-alpine3.24`, `postgres:18.6-alpine3.24`, `nginx:1.29.8-alpine`, `alpine:3.23.6`.
- Every command uses the FAKE demo password `demo-password-123`. Never reuse it for anything real.

## Files in this folder
| File | What it is |
|---|---|
| `catalog/seed.sql` | Creates the `courses` table and inserts DSA, System Design, DevOps |
| `catalog/site/index.html` | The course-catalog page nginx serves from a bind mount |
| `catalog/nginx/allcsvideos.conf` | A small nginx server block: `/health` and an `X-Served-By: catalog-dev` header |

Copy the folder out of the course repo first, because the lesson edits these files and writes backups next to them:
```bash
cp -R Devops_Course/docker/m06-l05-volumes-and-bind-mounts/catalog ~/catalog
cd ~/catalog
```
All names below start with `catalog-`. Volumes you create on purpose carry the label `lesson=m06l05`, so you can find and prune only them.

## Follow along

### 1. The hook: the catalog disappears (staged on purpose)
```bash
docker run -d --name catalog-db -e POSTGRES_PASSWORD=demo-password-123 -e POSTGRES_DB=catalog postgres:18.4-alpine3.24
docker exec -i catalog-db psql -U postgres catalog < seed.sql
docker exec catalog-db psql -U postgres catalog -c "SELECT * FROM courses"
```
Give Postgres a few seconds to start before the `psql` lines. You should see `CREATE TABLE`, `INSERT 0 3`, and three rows. Now "add a port" the way everyone does:
```bash
docker rm -f catalog-db
docker run -d --name catalog-db -e POSTGRES_PASSWORD=demo-password-123 -e POSTGRES_DB=catalog -p 5432:5432 postgres:18.4-alpine3.24
docker exec catalog-db psql -U postgres catalog -c "SELECT * FROM courses"
```
```
ERROR:  relation "courses" does not exist
```

### 2. Where did the data live?
```bash
docker diff catalog-db
docker inspect -f '{{range .Mounts}}{{.Type}} {{.Name}} {{.Destination}}{{end}}' catalog-db
docker image inspect -f '{{json .Config.Volumes}}' postgres:18.4-alpine3.24
docker exec catalog-db printenv PGDATA
```
```
C /run
C /run/postgresql
A /run/postgresql/.s.PGSQL.5432.lock
A /run/postgresql/.s.PGSQL.5432
volume 6f1f0d9b8e24...c843 /var/lib/postgresql
{"/var/lib/postgresql":{}}
/var/lib/postgresql/18/docker
```
The image declares a `VOLUME`, so every new container gets a fresh anonymous volume. The first container's volume is still on disk, as an orphan:
```bash
docker volume ls -q --filter dangling=true | wc -l
docker volume ls -q --filter dangling=true | xargs docker volume inspect -f '{{.CreatedAt}} {{.Name}}' | sort | tail -1
```
The newest dangling volume is the hook's (in the video: `587a9c...`; the count was 73 on that laptop, yours will differ). Rescue it:
```bash
OLD=<the long volume name printed above>
docker run -d --name catalog-rescue -e POSTGRES_PASSWORD=demo-password-123 --mount type=volume,src=$OLD,dst=/var/lib/postgresql postgres:18.4-alpine3.24
docker exec catalog-rescue psql -U postgres catalog -c "SELECT * FROM courses"
```
All three rows are back. Clean up, deleting the anonymous volumes with the containers (`-v`):
```bash
docker rm -f -v catalog-db catalog-rescue
docker volume rm $OLD
docker volume ls -q --filter dangling=true | wc -l
```

### 3. Named volumes
```bash
docker volume create --label lesson=m06l05 catalog-pgdata
docker volume ls --filter name=catalog-
docker volume inspect catalog-pgdata
```
```
"Mountpoint": "/var/lib/docker/volumes/catalog-pgdata/_data",
"Scope": "local"
```
On a Mac, that path is inside Docker Desktop's Linux VM, not on your Mac:
```bash
ls /var/lib/docker/volumes
docker run --rm --privileged --pid=host alpine:3.23.6 nsenter -t 1 -m ls /var/lib/docker/volumes/catalog-pgdata
docker run --rm --privileged --pid=host alpine:3.23.6 nsenter -t 1 -m df -h /var/lib/docker
```
```
ls: /var/lib/docker/volumes: No such file or directory
_data
/dev/vda1       911G   26G  839G   4% /var/lib/docker
```
(The two `--privileged` commands are a lab-only peek into the Docker Desktop VM. On a Linux server, use `sudo ls /var/lib/docker/volumes` instead.)

### 4. The postgres 18 mount-path trap
Most tutorials mount on `/var/lib/postgresql/data`. With postgres 18 that fails:
```bash
docker run -d --name catalog-db -e POSTGRES_PASSWORD=demo-password-123 -e POSTGRES_DB=catalog --mount type=volume,src=catalog-pgdata,dst=/var/lib/postgresql/data postgres:18.4-alpine3.24
sleep 3
docker ps -a --filter name=catalog-db --format '{{.Names}}  {{.Status}}'
docker logs catalog-db
docker rm -v catalog-db
```
```
catalog-db  Exited (1) 3 seconds ago
Error: in 18+, these Docker images are configured to store database data in a
       format which is compatible with "pg_ctlcluster" ...
       The suggested container configuration for 18+ is to place a single mount
       at /var/lib/postgresql ...
```
Mount at `/var/lib/postgresql` instead:
```bash
docker run -d --name catalog-db -e POSTGRES_PASSWORD=demo-password-123 -e POSTGRES_DB=catalog --mount type=volume,src=catalog-pgdata,dst=/var/lib/postgresql postgres:18.4-alpine3.24
docker inspect -f '{{range .Mounts}}{{.Type}} {{.Name}} {{.Destination}}{{end}}' catalog-db
docker exec -i catalog-db psql -U postgres catalog < seed.sql
```
`volume catalog-pgdata /var/lib/postgresql`: one mount, no anonymous volume.

### 5. The hook's test again, and a patch upgrade
```bash
docker rm -f catalog-db
docker run -d --name catalog-db -e POSTGRES_PASSWORD=demo-password-123 -e POSTGRES_DB=catalog --mount type=volume,src=catalog-pgdata,dst=/var/lib/postgresql postgres:18.4-alpine3.24
docker exec catalog-db psql -U postgres catalog -c "SELECT * FROM courses"

docker rm -f catalog-db
docker run -d --name catalog-db -e POSTGRES_PASSWORD=demo-password-123 -e POSTGRES_DB=catalog --mount type=volume,src=catalog-pgdata,dst=/var/lib/postgresql postgres:18.6-alpine3.24
docker exec catalog-db psql -U postgres catalog -c "SHOW server_version"
docker exec catalog-db psql -U postgres catalog -c "SELECT * FROM courses"
```
The rows survive both, and `server_version` is `18.6`. Patch upgrades are safe this way; a major upgrade (18 to 19) needs `pg_upgrade` or a dump and restore.

The short `-v` form, read-only:
```bash
docker run --rm -v catalog-pgdata:/var/lib/postgresql:ro alpine:3.23.6 ls /var/lib/postgresql/18/docker
```
You see real Postgres files: `PG_VERSION`, `base`, `global`, `pg_wal`, ...

### 6. Empty volume vs bind mount over the same folder
```bash
docker run -d --name catalog-vweb -p 8081:80 --mount type=volume,src=catalog-html,dst=/usr/share/nginx/html nginx:1.29.8-alpine
docker run --rm -v catalog-html:/html alpine:3.23.6 ls /html
curl -s localhost:8081 | grep title
```
```
50x.html
index.html
<title>Welcome to nginx!</title>
```
Docker copied the image's files into the new, empty volume. A bind mount hides them instead:
```bash
docker run -d --name catalog-bweb -p 8082:80 --mount type=bind,src=./site,dst=/usr/share/nginx/html nginx:1.29.8-alpine
docker exec catalog-bweb ls /usr/share/nginx/html
curl -s localhost:8082 | grep title
```
```
index.html
<title>allcsvideos - course catalog</title>
```

### 7. Bind mounts: typos, live edits, read-only
A typo with `--mount` is an error; with `-v` it silently creates an empty folder:
```bash
docker run --rm --mount type=bind,src=./stie,dst=/html alpine:3.23.6 ls /html
docker run --rm -v ./stie:/html alpine:3.23.6 ls /html
ls -d stie
rmdir stie
```
```
docker: Error response from daemon: invalid mount config for type "bind": bind source path does not exist: /host_mnt/.../catalog/stie
stie
```
Live editing, no rebuild, no restart:
```bash
curl -s localhost:8082
echo '<p>Kubernetes - coming soon</p>' >> site/index.html
curl -s localhost:8082
```
Read-only:
```bash
docker run -d --name catalog-ro --mount type=bind,src=./site,dst=/usr/share/nginx/html,readonly nginx:1.29.8-alpine
docker exec catalog-ro sh -c 'echo hacked > /usr/share/nginx/html/index.html'
```
```
sh: can't create /usr/share/nginx/html/index.html: Read-only file system
```

### 8. Config files: mount the folder, not the file
```bash
docker run -d --name catalog-web -p 8084:80 -v ./site:/usr/share/nginx/html:ro -v ./nginx/allcsvideos.conf:/etc/nginx/conf.d/default.conf:ro nginx:1.29.8-alpine
docker exec catalog-web nginx -t
curl -si localhost:8084/health
```
```
HTTP/1.1 200 OK
X-Served-By: catalog-dev

ok
```
Now edit the header with `sed -i` and reload (on Linux, drop the `''` after `-i`):
```bash
sed -i '' 's/catalog-dev;/catalog-dev-2;/' nginx/allcsvideos.conf
docker exec catalog-web nginx -s reload
```
In the video (Docker Desktop on a Mac) this failed for real:
```
nginx: [emerg] unexpected end of file, expecting "}" in /etc/nginx/conf.d/default.conf:10
```
`sed -i` writes a new file and renames it over the old one; a single-file bind mount stays pinned to the old file. On a Linux server it would quietly keep the old config instead. The fix is to mount the folder:
```bash
docker rm -f catalog-web
docker run -d --name catalog-web -p 8084:80 -v ./site:/usr/share/nginx/html:ro -v ./nginx:/etc/nginx/conf.d:ro nginx:1.29.8-alpine
sed -i '' 's/catalog-dev-2;/catalog-dev-3;/' nginx/allcsvideos.conf
docker exec catalog-web nginx -s reload
curl -si localhost:8084/health | grep X-Served
```
```
X-Served-By: catalog-dev-3
```

### 9. Ownership and speed
```bash
docker run --rm -v ./site:/site alpine:3.23.6 sh -c 'touch /site/report.html && ls -ln /site/report.html'
ls -ln site/report.html
docker run --rm -v ./site:/site alpine:3.23.6 grep /site /proc/mounts
rm -f site/report.html
```
Inside, the owner is `0` (root); on the Mac, `ls -ln` shows your own user ID (501 in the video), because Docker Desktop's virtiofs sharing uses a `fakeowner` layer. A Linux server has no such translation, which a volume on the VM's disk shows:
```bash
docker run --rm -v catalog-perm:/data alpine:3.23.6 sh -c 'touch /data/report.html && ls -ln /data'
docker run --rm --user 1000:1000 -v catalog-perm:/data alpine:3.23.6 touch /data/new.html
```
```
touch: /data/new.html: Permission denied
```
Speed: 5,000 small files in a bind mount vs a volume:
```bash
mkdir -p bench
docker run --rm -v ./bench:/d alpine:3.23.6 time sh -c 'for i in $(seq 5000); do echo x > /d/f$i; done'
docker run --rm --mount type=volume,src=catalog-bench,dst=/d alpine:3.23.6 time sh -c 'for i in $(seq 5000); do echo x > /d/f$i; done'
rm -rf bench
```
The video measured `real 0m 2.60s` for the bind mount and `real 0m 0.06s` for the volume.

### 10. tmpfs
```bash
docker run --rm --mount type=tmpfs,dst=/scratch,tmpfs-size=64m alpine:3.23.6 df -h /scratch
docker run --rm --tmpfs /scratch:size=64m alpine:3.23.6 dd if=/dev/zero of=/scratch/big bs=1M count=100
```
```
tmpfs                    64.0M         0     64.0M   0% /scratch
dd: error writing '/scratch/big': No space left on device
```
A FAKE secret that never touches a disk:
```bash
docker run -d --name catalog-tmp --mount type=tmpfs,dst=/run/secrets,tmpfs-size=1m alpine:3.23.6 sleep 3600
docker exec catalog-tmp sh -c 'echo FAKE-demo-token-123 > /run/secrets/token'
docker exec catalog-tmp ls /run/secrets
docker diff catalog-tmp
docker stop catalog-tmp
docker start catalog-tmp
docker exec catalog-tmp ls /run/secrets
```
`docker diff` shows only `C /run` and `A /run/secrets`; after stop/start the folder is empty.

### 11. Backup and restore
File-level copy, with the database stopped:
```bash
mkdir -p backup
docker stop catalog-db
docker run --rm --mount type=volume,src=catalog-pgdata,dst=/data,readonly -v ./backup:/backup alpine:3.23.6 tar czf /backup/pgdata.tgz -C /data .
ls -lhn backup
docker start catalog-db
```
Restore into a new volume and start Postgres on it:
```bash
docker volume create --label lesson=m06l05 catalog-pgdata2
docker run --rm -v catalog-pgdata2:/data -v ./backup:/backup alpine:3.23.6 tar xzf /backup/pgdata.tgz -C /data
docker run -d --name catalog-db2 -e POSTGRES_PASSWORD=demo-password-123 --mount type=volume,src=catalog-pgdata2,dst=/var/lib/postgresql postgres:18.6-alpine3.24
docker exec catalog-db2 psql -U postgres catalog -c "SELECT * FROM courses"
```
The database's own tool, while it runs:
```bash
docker exec catalog-db pg_dump -U postgres catalog > backup/catalog.sql
grep -E '^(CREATE TABLE|COPY|[0-9])' backup/catalog.sql
docker run -d --name catalog-db3 -e POSTGRES_PASSWORD=demo-password-123 -e POSTGRES_DB=catalog --mount type=volume,src=catalog-pgdata3,dst=/var/lib/postgresql postgres:18.6-alpine3.24
docker exec -i catalog-db3 psql -q -U postgres catalog < backup/catalog.sql
docker exec catalog-db3 psql -U postgres catalog -c "SELECT * FROM courses"
```
```
CREATE TABLE public.courses (
COPY public.courses (id, title) FROM stdin;
1	DSA
2	System Design
3	DevOps
```

### 12. Sharing a volume
```bash
docker run -d --name catalog-writer --mount type=volume,src=catalog-shared,dst=/out alpine:3.23.6 sh -c 'while true; do date > /out/index.html; sleep 1; done'
docker run -d --name catalog-reader -p 8085:80 --mount type=volume,src=catalog-shared,dst=/usr/share/nginx/html,readonly nginx:1.29.8-alpine
curl -s localhost:8085
sleep 2
curl -s localhost:8085
docker run --rm --volumes-from catalog-writer alpine:3.23.6 cat /out/index.html
```
The time moves on between the two `curl`s (16:34:00, then 16:34:02 in the video).

### 13. Deleting volumes
```bash
docker volume create --label lesson=m06l05 catalog-scratch
docker volume ls --filter label=lesson=m06l05
docker volume rm catalog-pgdata
```
```
Error response from daemon: remove catalog-pgdata: volume is in use - [...]
```
Prune only this lesson's unused volumes:
```bash
docker volume prune -a -f --filter label=lesson=m06l05
```
Only `catalog-scratch` is deleted. Now the danger (staged on purpose): remove the container that uses `catalog-pgdata2`, and prune again:
```bash
docker rm -f catalog-db2
docker volume prune -a -f --filter label=lesson=m06l05
```
```
Deleted Volumes:
catalog-pgdata2

Total reclaimed space: 48.57MB
```
No confirmation, no undo. Never prune without a filter on a shared machine. (Coming in module 7: `docker compose down -v` deletes a stack's volumes too.)

## Common mistakes
1. Data in the container layer or in an anonymous volume: it vanishes with `docker rm -v`, or becomes an orphan. Give lasting data a named volume.
2. Bind-mounting over a populated folder (for example your project over `/app`) hides what the image put there, like installed dependencies or built files.
3. Anonymous volume sprawl (72 orphans on the video's laptop): use `--rm` for throwaway containers, `docker rm -v`, and prune with a filter.
4. Deleting data by accident: `docker volume rm`, `prune -a` and `compose down -v` never ask twice.
5. Assuming volumes are backed up. They aren't: dump, copy off the machine, and test the restore.
6. Also from the lesson: mounting postgres 18 on `/var/lib/postgresql/data`, `-v` typos that silently create empty folders, and single-file bind mounts for config you edit.

## Clean up
```bash
docker rm -f -v catalog-db catalog-db2 catalog-db3 catalog-vweb catalog-bweb catalog-ro catalog-web catalog-tmp catalog-writer catalog-reader 2>/dev/null
docker volume rm catalog-pgdata catalog-pgdata2 catalog-pgdata3 catalog-html catalog-perm catalog-bench catalog-shared catalog-scratch 2>/dev/null
rm -rf ~/catalog
```

## Next
[M06-L06 · Container Networking](../m06-l06-container-networking/)
