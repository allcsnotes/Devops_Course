# M09-L04 · Versioning and Rollback
> Video: Module 9, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- **You can roll back code, not data**: an image goes back in seconds, the schema only moves forward.
- Version and trace every release: semver vs CalVer, and one chain where the git tag, image tag, digest and the
  version the service reports all name the same commit.
- Conventional Commits + **git-cliff**: the next version number and the changelog from the commit messages; release
  notes written for people.
- **Expand, migrate, contract** (parallel change): a column rename as three releases, each compatible with the one
  before, so a rollback is always one step back.
- Which schema changes are safe in one step, why Flyway Community has no undo, and the ways back (redeploy the
  previous digest, roll forward, flag off, restore a backup as the last resort).

## Before you start
- Docker Desktop with Compose v2.20+, `make`, `git`, `jq`, `curl`. About 3 GB free disk (Java builds).
- The course app: [`../../allcsvideos/`](../../allcsvideos/README.md) (Module 7, Build 1). You work on your own copy.
- Pinned: `postgres:18.6-alpine3.24`, `redis:8.10.2-alpine3.23`, `flyway/flyway:12.4.0-alpine`, `registry:3.1.2`,
  `orhunp/git-cliff:2.14.2`.
- In the commands below, `L=<path-to-this-lesson-folder>`. All local, no GitHub needed. The video's lab used its own
  ports (8494, 5494); your copy keeps the app's defaults: storefront `127.0.0.1:8080`, registry `127.0.0.1:5001`.

## Files in this folder
`J` = `api/catalog-service/src/main/java/com/allcs/catalog`, `M` = `api/catalog-service/src/main/resources/db/migration`.

| File | What it is |
|---|---|
| `changes/setup/` | Before v1.0.0: migrations ship as an image (`compose.yaml` `migrate` build), `/actuator/info` shows version + commit (`api/Dockerfile` `GIT_SHA`, `application.yml`), `scripts/release.sh` (refuses to build without the git tag), `scripts/deploy.sh` (by digest), `Makefile` targets `deploy info course backup restore` |
| `changes/v1.1.0/` | The one-step rename (staged mistake): `M/V3__rename_title_to_name.sql` + `J/CourseCatalog.java`, `J/CourseController.java` (add-course endpoint) |
| `changes/changelog/cliff.toml` | git-cliff config: commit types -> groups, skips its own release commits |
| `changes/v1.2.0/` | EXPAND: `M/V3__expand_add_course_name.sql`, code writes both columns, reads `coalesce(name, title)`; `release-notes-1.2.0.md` |
| `changes/v1.2.1/` | MIGRATE: `M/V4__migrate_course_name.sql`, code reads and writes `name` only |
| `changes/v1.2.2/` | CONTRACT: `M/V5__contract_drop_title.sql` |
| `changes/changelog/CHANGELOG-final.md` | What CHANGELOG.md looked like at the end of the video (for comparison) |

## Follow along

1. **Your copy of the app, with the release tooling.**
   ```bash
   cp -R $L/../../allcsvideos ~/allcsvideos-lab
   cd ~/allcsvideos-lab
   git init -b main && git add -A && git commit -qm 'allcsvideos platform (M07-B01)'
   git remote add origin https://github.com/<you>/allcsvideos-lab.git   # release.sh records it; pushing is optional
   cp -R $L/changes/setup/. .
   git add -A && git commit -qm 'feat(catalog): show the version and git commit in /actuator/info'
   make registry
   make up
   ```
   `make up` builds and starts the whole stack (first run takes a while). Then release and deploy 1.0.0:
   ```bash
   git tag -a v1.0.0 -m "catalog 1.0.0"
   make release VERSION=1.0.0
   make deploy VERSION=1.0.0
   make info
   ```

2. **The hook (staged): a one-step rename.** Priya's 1.1.0 renames `courses.title` to `name` and adds an add-course
   endpoint:
   ```bash
   C=$L/changes/v1.1.0
   cp -R $C/api/catalog-service/src/main/resources/. api/catalog-service/src/main/resources/
   cp $C/api/catalog-service/src/main/java/com/allcs/catalog/CourseCatalog.java api/catalog-service/src/main/java/com/allcs/catalog/
   git add -A && git commit -qm 'refactor(db): rename courses.title to name'
   cp $C/api/catalog-service/src/main/java/com/allcs/catalog/CourseController.java api/catalog-service/src/main/java/com/allcs/catalog/
   git commit -qam 'feat(catalog): instructors can add a course'
   git log --oneline v1.0.0..
   git tag -a v1.1.0 -m "catalog 1.1.0"
   make release VERSION=1.1.0
   make backup
   make deploy VERSION=1.1.0
   curl -s 127.0.0.1:8080/api/courses | jq -c '.[0]'
   ```
   Flyway applies migration 3 and the list answers. Now rehearse the rollback:
   ```bash
   make deploy VERSION=1.0.0
   curl -s -o /dev/null -w 'HTTP %{http_code}\n' 127.0.0.1:8080/api/courses
   docker compose logs --no-log-prefix catalog | grep -oE 'bad SQL grammar \[[^]]*\]|PSQLException: .*' | head -2
   ```
   Flyway warns `Schema "public" has a version (3) that is newer than the latest available migration (2)`, catalog is
   healthy, but the list says `HTTP 500`: `ERROR: column "title" does not exist`. The image went back; the database
   didn't. Roll forward: `make deploy VERSION=1.1.0`.

3. **The trace.** Git tag, image, digest and running version name one commit:
   ```bash
   make info
   git rev-parse --short v1.1.0^{commit}
   cat dist/release-1.1.0.txt
   docker image inspect localhost:5001/do-m07b01/catalog:1.1.0 --format '{{json .Config.Labels}}' | jq
   ```
   `scripts/release.sh` refuses to build unless HEAD carries `v<VERSION>`; `scripts/deploy.sh` deploys the digests from
   `dist/release-<VERSION>.txt`, never a tag. The migrate job runs first, then catalog. A rollback is the same command
   with an older version.

4. **Put staging back (last resort: a restore), then revert on main.**
   ```bash
   ls dist/*.dump
   make restore F=dist/catalog-<timestamp>.dump
   make deploy VERSION=1.0.0
   curl -s -o /dev/null -w 'HTTP %{http_code}\n' 127.0.0.1:8080/api/courses
   ```
   `pg_restore --clean` replaces the tables, including Flyway's history. Anything written after the backup is gone.
   Now revert 1.1.0 in one commit (the tag v1.1.0 stays: a version that shipped is never reused):
   ```bash
   git rm -q api/catalog-service/src/main/resources/db/migration/V3__rename_title_to_name.sql
   git checkout v1.0.0 -- api/catalog-service
   git commit -qm 'revert: undo 1.1.0, the one-step rename of courses.title'
   ```

5. **Expand (1.2.0), with a changelog.**
   ```bash
   cp $L/changes/changelog/cliff.toml cliff.toml
   git add cliff.toml && git commit -qm 'chore: add the git-cliff changelog config'
   C=$L/changes/v1.2.0
   cp -R $C/api/catalog-service/src/main/resources/. api/catalog-service/src/main/resources/
   cp $C/api/catalog-service/src/main/java/com/allcs/catalog/CourseCatalog.java api/catalog-service/src/main/java/com/allcs/catalog/
   git add -A && git commit -qm 'refactor(db): expand, add courses.name next to courses.title'
   cp $C/api/catalog-service/src/main/java/com/allcs/catalog/CourseController.java api/catalog-service/src/main/java/com/allcs/catalog/
   git commit -qam 'feat(catalog): instructors can add a course'
   ```
   Migration 3 adds `name` (nullable) and copies every title into it; reads use `coalesce(name, title) as title`; the
   add-course endpoint writes both columns.
   ```bash
   git log --oneline v1.1.0..
   alias git-cliff='docker run --rm -v "$PWD":/app orhunp/git-cliff:2.14.2'
   git-cliff --bumped-version
   git-cliff --unreleased --bump
   ```
   `v1.2.0` (a `feat` since the last tag -> MINOR; it warns about older commits without the convention). Check the
   rules on a throwaway branch:
   ```bash
   git switch -qc try-bumps
   git commit -q --allow-empty -m 'fix(catalog): return 404 for an unknown course id'
   git-cliff --bumped-version 2>/dev/null
   git commit -q --allow-empty -m 'feat(catalog)!: prices in cents' -m 'BREAKING CHANGE: priceEur is now priceCents'
   git-cliff --bumped-version 2>/dev/null
   git switch -q main && git branch -qD try-bumps
   ```
   `v1.2.1` (PATCH), then `v2.0.0` (MAJOR). Back on main, write the changelog, tag and release:
   ```bash
   git-cliff --bump -o CHANGELOG.md
   git add CHANGELOG.md && git commit -qm "chore(release): prepare for v1.2.0"
   git tag -a v1.2.0 -m "catalog 1.2.0"
   make release VERSION=1.2.0
   cat $L/changes/v1.2.0/release-notes-1.2.0.md
   ```
   The changelog is for developers; the release notes answer three questions for people: what's new, who has to do
   something, and is it safe to roll back.

6. **Deploy 1.2.0 and prove the rollback.**
   ```bash
   make deploy VERSION=1.2.0
   make course ID=K8S-101 TITLE=Kubernetes
   make deploy VERSION=1.0.0
   curl -s 127.0.0.1:8080/api/courses | jq -r '.[] | .id + "  " + .title'
   docker compose exec db psql -U catalog -c 'select id, title, name from courses order by id'
   make deploy VERSION=1.2.0
   ```
   The same Flyway warning, and this time the list answers: six courses, including Kubernetes, which 1.2.0 wrote.
   Both columns are filled in every row; 1.0.0 reads `title` and never notices `name`. Forward again: `Schema "public"
   is up to date. No migration necessary.`

7. **Migrate (1.2.1).**
   ```bash
   cp -R $L/changes/v1.2.1/api/. api/
   git add -A && git commit -qm 'refactor(catalog): migrate, read and write only courses.name'
   git-cliff --bumped-version
   git-cliff --bump -o CHANGELOG.md 2>/dev/null
   git commit -qam 'chore(release): prepare for v1.2.1' && git tag -a v1.2.1 -m 'catalog 1.2.1'
   make release VERSION=1.2.1
   make deploy VERSION=1.2.1
   make course ID=TF-101 TITLE=Terraform 2>/dev/null
   docker compose exec db psql -U catalog -c 'select id, title, name from courses order by id'
   ```
   Migration 4 fills `name` for rows 1.0.0 might have written, makes it `NOT NULL`, and lets `title` be empty.
   Terraform has a name and an empty title. Rollback to 1.2.0 still works (`make deploy VERSION=1.2.0`, then back to
   1.2.1); 1.0.0 is no longer a rollback target (it would show an empty title).

8. **Contract (1.2.2).** Dropping a column deletes data, so back up first:
   ```bash
   make backup
   cp -R $L/changes/v1.2.2/api/. api/
   git add -A && git commit -qm 'refactor(db): contract, drop courses.title'
   git-cliff --bump -o CHANGELOG.md 2>/dev/null
   git commit -qam 'chore(release): prepare for v1.2.2' && git tag -a v1.2.2 -m 'catalog 1.2.2'
   make release VERSION=1.2.2
   make deploy VERSION=1.2.2
   docker compose exec db psql -U catalog -c '\d courses' | head -8
   ```
   The table now has `id`, `price_eur`, `seats_left`, `name`; no `title`. The rollback window, proved:
   ```bash
   make deploy VERSION=1.2.1 | tail -1
   curl -s -o /dev/null -w 'HTTP %{http_code}\n' 127.0.0.1:8080/api/courses     # 200
   make deploy VERSION=1.0.0 | tail -1
   curl -s -o /dev/null -w 'HTTP %{http_code}\n' 127.0.0.1:8080/api/courses     # 500: the hook's error
   make deploy VERSION=1.2.2 | tail -1
   docker compose exec db psql -U catalog -c 'select version, description, success from flyway_schema_history order by installed_rank'
   ```

9. **Couldn't Flyway just undo?**
   ```bash
   docker compose run --rm --no-deps --entrypoint flyway migrate undo
   git tag -n
   ```
   `ERROR: undo is not supported by the OSS Edition` (Community). Teams edition needs a hand-written undo script per
   migration; no undo script can bring back a dropped column's data. Most teams go forward-only with expand and
   contract, and keep backups for disasters.

**Safe in one step?** Adding a nullable column or a new table: yes. An index: yes, but on a big PostgreSQL table use
`CREATE INDEX CONCURRENTLY`. Renaming a column or table: no. Dropping a column: not before the contract step. Adding
`NOT NULL` without a default: no. Changing a type: like a rename, expand and contract.

**Ways back:** redeploy the previous digest (about 9 s here, the default while the schema is compatible); roll forward
with a fix (when data already moved on); turn the feature flag off (lesson 3, no deploy at all); restore a backup
(last resort, loses everything written since).

## Common mistakes
- **Coupling deploy and migration in one irreversible step**, like the rename in the hook. Expand, migrate, contract.
- **Migrations that lock big tables.** Build indexes concurrently, backfill in batches.
- **A changelog nobody reads.** Generate the changelog; write the release notes for people.
- **Untagged releases.** Which commit is 1.0.1? `release.sh` now refuses to build without the tag.
- **A rollback nobody has practised.** Rehearse it on staging for every release that touches the schema.

## Clean up
```bash
cd ~/allcsvideos-lab
make nuke                          # stops the stack, deletes its database volume and local images
docker rm -f do-m07b01-registry && docker volume rm do-m07b01-registry-data
rm -rf ~/allcsvideos-lab           # optional
```

## Next
[M09-L05 · Jenkins and GitLab CI](../m09-l05-jenkins-and-gitlab-ci/)
