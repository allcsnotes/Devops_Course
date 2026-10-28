#!/usr/bin/env bash
# prep.sh <demo> - prepares, as asha, the small demo repositories whose starting history the video set up off screen.
#   android     ~/allcsvideos-android with three commits (App 2.2.0, playback speed, free storage)   (step 6)
#   merge-demo  ~/merge-demo: main + feature/player-speed (3 commits), main moved on by one         (step 7)
#   env-demo    ~/env-demo: dev / staging / prod branches, one hotfix made directly on prod          (step 9)
#   search      in ~/merge-demo: feature/search with main merged in three times, and a rebased copy (step 9)
set -euo pipefail
as() { docker exec -u asha -w /home/asha git-team bash -c "$1"; }
case "${1:-}" in
  android) as "git init -q allcsvideos-android && cd allcsvideos-android && echo 'versionName=2.2.0' > version.properties && echo 'class Player' > Player.kt && git add . && git commit -qm 'App 2.2.0'
              echo 'fun speed() {}' >> Player.kt && git commit -qam 'Player: playback speed menu'
              echo 'class Downloads' > Downloads.kt && git add . && git commit -qm 'Downloads: check free storage first'" ;;
  merge-demo) as "git init -q merge-demo && cd merge-demo && echo 'class Player' > Player.kt && git add . && git commit -qm 'Player: first version'
              git switch -q -c feature/player-speed && echo 'speeds=1,1.5,2' > Speed.kt && git add . && git commit -qm 'Player: speed menu'
              echo 'save=true' >> Speed.kt && git commit -qam 'Player: remember the speed' && echo 'label=Speed' >> Speed.kt && git commit -qam 'Player: fix the menu label'
              git switch -q main && echo '# merge-demo' > README.md && git add . && git commit -qm 'README: build badges'" ;;
  env-demo) as "git init -q env-demo && cd env-demo && echo 'v=1' > app.txt && git add . && git commit -qm 'App 1.0' && git branch staging && git branch prod && git switch -q -c dev
              echo coupons >> app.txt && git commit -qam 'Checkout: coupons' && echo search >> app.txt && git commit -qam 'Search: faster' && echo captions >> app.txt && git commit -qam 'Player: captions'
              git switch -q staging && git merge -q --no-ff --no-edit dev~1 && git switch -q prod && git merge -q --no-ff --no-edit staging
              echo 'timeout=30' > pay.txt && git add . && git commit -qm 'Hotfix: payment timeout' && git switch -q dev" ;;
  search) as "cd merge-demo && git switch -q main && git switch -q -c feature/search main
              echo a > Search.kt && git add . && git commit -qm 'Search: box' && git switch -q main && echo 1 >> README.md && git commit -qam 'README: install' && git switch -q feature/search && git merge -q --no-edit main
              echo b >> Search.kt && git commit -qam 'Search: results' && git switch -q main && echo 2 >> README.md && git commit -qam 'README: usage' && git switch -q feature/search && git merge -q --no-edit main
              echo c >> Search.kt && git commit -qam 'Search: filters' && git switch -q main && echo 3 >> README.md && git commit -qam 'README: license' && git switch -q feature/search && git merge -q --no-edit main
              git switch -q -c feature/search-rebased main && (git cherry-pick main..feature/search --no-merges >/dev/null 2>&1 || true); git switch -q main" ;;
  *) sed -n '2,7p' "$0"; exit 1 ;;
esac
echo "prepared: $1"
