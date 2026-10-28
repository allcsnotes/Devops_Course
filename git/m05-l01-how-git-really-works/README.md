# M05-L01 · How Git Really Works
> Video: Module 5, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- Git is a content-addressed key-value store: the same content always gets the same hash.
- The four object types (blob, tree, commit, annotated tag), how they're hashed and where they live in `.git/objects`.
- Refs: a branch is a 41-byte file holding a hash, `HEAD` points to a branch (or straight at a commit when detached).
- The three areas (working tree, index, repository) and how `git add`, `git diff`, `git diff --staged`, `git add -p` and `git restore` move between them.
- How to rescue a "lost" commit from detached HEAD with `git branch` and `git reflog`.
- Packfiles and `git gc`, SHA-1 vs SHA-256, and four pitfalls: committed secrets, `.gitignore`, large binaries, CRLF line endings.

## Before you start
- Git set up as in [M01-L03](../../setup/m01-l03-setting-up-your-devops-lab/) (name, email, `init.defaultBranch main`).
- The video runs on a clean Ubuntu 24.04 "laptop" with Git 2.43.0. To get exactly the same tools (GNU `sed`, `sha1sum`, `tree`, `head -c 20M`),
  use the small lab container in `lab/` (needs Docker Desktop). On Linux or WSL you can also use your own terminal: install `tree`, copy the
  `hc/` folder to `~/hc`, and set your identity.
- The `hc/` files are two files from the health-check toolkit built in module 3.

## Files in this folder
| File | What it is |
|------|------------|
| `hc/README.md`, `hc/conf/hc.conf` | The toolkit's README and config, copied into the new repository in step 3 |
| `lab/Dockerfile` | Ubuntu 24.04 + Git 2.43.0, `tree`, time zone Asia/Kolkata |
| `lab/up.sh` | Starts the `git-laptop` container, puts the `hc` files in `~/hc`, sets the identity `Asha <asha@example.com>` |
| `lab/down.sh` | Removes the container and image |

**About hashes:** blob and tree hashes depend only on content, so yours will match the video (`d377f60`, `fd3259f`, `79fbf46`...).
Commit and tag hashes also include the author, time and parent, so yours will be different (`a3c9215`, `7c66c89`, `9942875`...).
Wherever a step uses a commit hash, use the one **your** terminal printed.

## Follow along

1. Start the laptop and check Git:
   ```bash
   bash lab/up.sh
   docker exec -it -u asha -w /home/asha git-laptop bash
   ```
   ```bash
   git --version
   git config --global --list
   ```
   `git version 2.43.0`, `user.name=Asha`, `user.email=asha@example.com`, `init.defaultbranch=main`.

2. Create the repository and look inside `.git`:
   ```bash
   mkdir allcsvideos-ops && cd allcsvideos-ops
   git init
   ls -A
   ls .git
   tree .git
   cat .git/HEAD
   ls .git/refs/heads
   ```
   `HEAD  branches  config  description  hooks  info  objects  refs`, 14 sample hooks, an empty `objects` store, and
   `ref: refs/heads/main` although `refs/heads` is still empty: main is born with the first commit.

3. Add files and hash them:
   ```bash
   echo '# allcsvideos-ops' > README.md
   echo 'Ops scripts and configs for allcsvideos.com' >> README.md
   mkdir hc && cp ~/hc/README.md ~/hc/conf/hc.conf hc/
   tree
   git hash-object README.md
   cp README.md /tmp/copy.md
   git hash-object /tmp/copy.md
   wc -c README.md
   printf 'blob 62\0' | cat - README.md | sha1sum
   sed 's/com$/com./' README.md | git hash-object --stdin
   find .git/objects -type f
   ```
   You should see `d377f6052aaa851929d274b6268b3c73dee62e42` three times (the name is not part of a blob, and `sha1sum` over
   `blob 62\0` + the content is exactly Git's key), `62 README.md`, `56d1daa...` after a one-character change, and still no objects.

4. Stage and look at the index:
   ```bash
   git add .
   find .git/objects -type f
   git ls-files --stage
   git cat-file -t d377f60
   git cat-file -p d377f60
   git status
   ```
   ```
   100644 d377f6052aaa851929d274b6268b3c73dee62e42 0       README.md
   100644 3d633412b071b36cf5594096a7697d9f6a23fff8 0       hc/README.md
   100644 81fb6bcc2babb055e8183c4166f21233192ee664 0       hc/hc.conf
   blob
   ```

5. The first commit, and its trees:
   ```bash
   git commit -m 'Add README and hc toolkit config'
   find .git/objects -type f | wc -l
   git cat-file -t HEAD
   git cat-file -p HEAD
   git cat-file -p fd3259f
   git cat-file -p 79fbf46
   ```
   ```
   [main (root-commit) a3c9215] Add README and hc toolkit config
   6
   commit
   tree fd3259f05ecc3ca759330b2b238c692802d3571a
   author Asha <asha@example.com> 1792502523 +0530
   ...
   100644 blob d377f6052aaa851929d274b6268b3c73dee62e42    README.md
   040000 tree 79fbf46fdb0a9a495983c307d0debf82f2d33ff4    hc
   ...
   100644 blob 3d633412b071b36cf5594096a7697d9f6a23fff8    README.md
   100644 blob 81fb6bcc2babb055e8183c4166f21233192ee664    hc.conf
   ```
   One commit, two trees, three blobs: six objects.

6. Change one file:
   ```bash
   sed -i 's/^SERVICES=.*/SERVICES=nginx allcsvideos-api course-copilot/' hc/hc.conf
   git commit -am 'hc: also check course-copilot'
   git cat-file -p HEAD
   git cat-file -p 1097168
   git cat-file -p c816ed8
   find .git/objects -type f | wc -l
   ```
   The new commit has `tree 1097168...` and `parent <your first commit>`. `README.md` is still blob `d377f60`, `hc/README.md` still `3d63341`;
   only `hc.conf` has a new blob `ff48c81`, plus new trees for every folder above it. Four new objects, `10` in total.

7. Refs, branches and tags (use your own first-commit hash for `v0.1`):
   ```bash
   cat .git/HEAD
   cat .git/refs/heads/main
   wc -c .git/refs/heads/main
   git branch alerts-v2
   ls .git/refs/heads
   cat .git/refs/heads/alerts-v2
   git branch
   git switch alerts-v2
   cat .git/HEAD
   git switch main
   cat .git/HEAD
   git tag v0.1 <first-commit-hash>
   git tag -a v0.2 -m 'hc config with course-copilot'
   cat .git/refs/tags/v0.1
   cat .git/refs/tags/v0.2
   git cat-file -t v0.1
   git cat-file -t v0.2
   git cat-file -p v0.2
   ```
   A branch file is `41` bytes (40 hex characters and a newline). `v0.1` is a `commit`; `v0.2` is a `tag` object with `object`, `type`, `tag`, `tagger` and the message.

8. The three areas:
   ```bash
   git status
   echo 'Toolkit docs: hc/README.md' >> README.md
   sed -i 's/^DISK_WARN=80/DISK_WARN=75/; s/^HTTP_TIMEOUT=3/HTTP_TIMEOUT=5/' hc/hc.conf
   git status
   git diff
   git add README.md
   git status
   git diff --stat
   git diff --staged
   ```
   `git diff` shows `index d377f60..a071f99` for README.md and two hunks in `hc.conf`. After `git add README.md`, `git diff --stat` shows only
   `hc/hc.conf | 4 ++--` (working tree vs index) and `git diff --staged` shows the README line (index vs last commit).

9. Stage only part of a file. Answer `y` for hunk 1 (the disk warning) and `n` for hunk 2 (the timeout):
   ```bash
   git add -p hc/hc.conf
   git status --short
   git rev-parse HEAD:hc/hc.conf
   git rev-parse :hc/hc.conf
   git hash-object hc/hc.conf
   ```
   ```
   M  README.md
   MM hc/hc.conf
   ff48c8143300938776d4944f9676472bac5a2b2e
   8c514becba5b7031d6d4061ce618ce4f7dab9933
   51f383d1181643089ae08dff7059a7570b6593f0
   ```
   Three areas, three blobs.

10. Undo with `git restore`, then make two small commits:
    ```bash
    git restore hc/hc.conf
    git restore --staged README.md
    git status --short
    grep -n TIMEOUT hc/hc.conf
    git commit -m 'hc: warn at 75% disk'
    git add README.md
    git commit -m 'README: link the toolkit docs'
    git status
    ```
    `git restore hc/hc.conf` throws away the unstaged edit for good (`16:HTTP_TIMEOUT=3`). `git restore --staged` only unstages.

11. Priya's scare: detached HEAD (use your first-commit hash, or `v0.1`):
    ```bash
    git checkout <first-commit-hash>
    cat .git/HEAD
    echo 'Owner: the allcsvideos ops team' >> README.md
    git commit -am 'README: add the owner'
    git switch main
    git log --oneline --all
    ```
    `You are in 'detached HEAD' state`, `.git/HEAD` holds a bare hash, and switching back warns:
    ```
    Warning: you are leaving 1 commit behind, not connected to
    any of your branches:
      9942875 README: add the owner
    ```
    `git log --oneline --all` doesn't list it, but nothing was deleted.

12. Rescue it (use the hash from the warning, or find it in the reflog):
    ```bash
    git reflog
    git branch readme-owner <hash-from-the-warning>
    git log --oneline --graph --all
    ```
    ```
    * 9942875 (readme-owner) README: add the owner
    | * 996a01f (HEAD -> main) README: link the toolkit docs
    | * 01255d8 hc: warn at 75% disk
    | * 7c66c89 (tag: v0.2, alerts-v2) hc: also check course-copilot
    |/
    * a3c9215 (tag: v0.1) Add README and hc toolkit config
    ```
    The reflog is local, and entries for unreachable commits are kept for 30 days by default. Better: start experiments with `git switch -c`.

13. Packfiles and `git gc`:
    ```bash
    git count-objects -v
    git gc
    git count-objects -v
    ls .git/objects/pack
    ls .git/refs/heads
    cat .git/packed-refs
    git rev-parse main
    git verify-pack -v .git/objects/pack/pack-*.idx | grep blob
    ```
    21 loose objects (84 KB) become 1 pack (5 KB). `refs/heads` is empty now: every ref moved into `packed-refs`, so in scripts
    always ask Git (`git rev-parse main`) instead of reading branch files. `verify-pack` shows the newest `hc.conf` (`8c514be`) stored whole
    and the older `ff48c81` as a small delta against it.

14. SHA-1 and SHA-256:
    ```bash
    git rev-parse --show-object-format
    git init -q --object-format=sha256 ~/sha256-demo
    cd ~/sha256-demo
    git rev-parse --show-object-format
    git hash-object ~/allcsvideos-ops/README.md
    cd ~/allcsvideos-ops
    git hash-object README.md
    ```
    `sha1`, then `sha256` with a 64-character hash for the same README (`a73360a7...`), vs 40 characters (`a071f99...`).

15. Pitfall 1: a committed secret (the token is **fake**):
    ```bash
    sed -i 's|^WEBHOOK_URL=.*|WEBHOOK_URL=https://hooks.example.com/FAKE-demo-token-123|' hc/hc.conf
    git commit -qam 'hc: use the team webhook'
    sed -i 's|^WEBHOOK_URL=.*|WEBHOOK_URL=http://hooks:9000/hc|' hc/hc.conf
    git commit -qam 'hc: remove the webhook token'
    grep WEBHOOK hc/hc.conf
    git log --oneline -S FAKE-demo-token-123
    git show HEAD~1:hc/hc.conf | grep WEBHOOK
    ```
    The file is clean, the history isn't: both commits are listed and the old version still shows the token.

16. Pitfall 2: `.gitignore`:
    ```bash
    echo 'WEBHOOK_URL=https://hooks.example.com/FAKE-demo-token-123' > .env
    echo 'run at 19:02 OK' > hc.log
    git status --short
    printf '.env\n*.log\n' > .gitignore
    git status --short
    git check-ignore -v .env hc.log
    git add .gitignore && git commit -qm 'Ignore .env and log files'
    git status --short
    ```
    `?? .env` and `?? hc.log` become just `?? .gitignore`; `check-ignore -v` names the line that ignores each file.

17. Pitfall 3: large binaries, in a scratch repository:
    ```bash
    git init -q ~/media-demo && cd ~/media-demo
    head -c 20M /dev/urandom > intro.mp4 && git add intro.mp4 && git commit -qm 'Add intro video'
    head -c 20M /dev/urandom > intro.mp4 && git commit -qam 'New intro video'
    git rm -q intro.mp4 && git commit -qm 'Remove the video'
    ls
    git count-objects -vH | grep -E '^(count|size):'
    cd ~/allcsvideos-ops
    ```
    The folder is empty, but `size: 40.04 MiB`: every version stays in history.

18. Pitfall 4: CRLF line endings:
    ```bash
    printf '#!/bin/bash\r\necho ok\r\n' > hc/check.sh
    git add hc/check.sh
    git ls-files --eol hc/check.sh
    git config core.autocrlf
    echo '*.sh text eol=lf' > .gitattributes
    git add .gitattributes && git add --renormalize .
    git ls-files --eol hc/check.sh
    chmod +x hc/check.sh && ./hc/check.sh
    rm hc/check.sh && git restore hc/check.sh
    git ls-files --eol hc/check.sh
    chmod +x hc/check.sh && ./hc/check.sh
    git add hc/check.sh && git commit -qm 'Add check.sh, LF line endings for scripts'
    git status --short
    ```
    ```
    i/crlf  w/crlf  attr/                   hc/check.sh
    i/lf    w/crlf  attr/text eol=lf        hc/check.sh
    -bash: ./hc/check.sh: cannot execute: required file not found
    i/lf    w/lf    attr/text eol=lf        hc/check.sh
    ok
    ```

## Common mistakes
- **Committing a secret.** A follow-up commit doesn't remove it from history. Revoke and replace the secret first; history rewriting and secret scanning come in module 18.
- **Expecting `.gitignore` to hide tracked files.** It only affects untracked files; use `git rm --cached` for a file Git already tracks.
- **Committing large binaries.** Every version stays in every clone forever. Use object storage or Git LFS.
- **Relying on `core.autocrlf`.** It's a personal setting (Git for Windows sets it to `true`). A `.gitattributes` file travels with the repository and works for everyone.
- **Working in detached HEAD.** Commits there belong to no branch. Use `git switch -c`, and rescue strays quickly with `git reflog`.
- **Reading `.git/refs/heads/*` in scripts.** After `git gc` refs live in `packed-refs`; use `git rev-parse`.

## Clean up
Inside the container nothing touches your computer. Remove it all with:
```bash
bash lab/down.sh
```
(If you followed along in your own terminal instead: `rm -rf ~/allcsvideos-ops ~/sha256-demo ~/media-demo ~/hc /tmp/copy.md`.)

## Next
[M05-L02 · Branching Strategies](../m05-l02-branching-strategies/)
