# M09-L03 · Feature Flags
> Video: Module 9, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- **Deploy is not release**: code ships dark behind a flag, and a flag change releases it, with no build and no
  redeploy.
- The four kinds of flags (release, experiment, ops, permission) and how long each should live.
- How a flag is evaluated: OpenFeature SDK -> provider -> flagd; targeting rules (staff, beta), and a **sticky**
  percentage rollout (hash of flag + user into a bucket).
- An ops flag as a **kill switch** for a failing dependency, and choosing safe code defaults for when the flag service
  is down.
- Flags are debt: owner, type, expiry date, a CI check, and really removing an old flag (Knight Capital, 2012).

## Before you start
- Docker Desktop and a terminal for the runtime lab (`lab/`, all local).
- For the clean-up part: your `allcsvideos-ops` repo on GitHub from Module 8, with its `hc` tests workflow
  (`hc.yml` from [M08-L03](../m08-l03-build-test-and-lint/)).
- Pinned: `ghcr.io/open-feature/flagd:v0.18.0`, `nginx:1.29.8-alpine`, `python:3.12.15-slim`, OpenFeature SDK
  `openfeature-sdk==0.10.0`, `openfeature-provider-flagd==0.6.0`.
- In the commands below, `L=<path-to-this-lesson-folder>`.
- The clean-up part ran on the local Gitea lab in the video; the optional offline route is
  [`../m08-l01-what-ci-is/gitea-lab/`](../m08-l01-what-ci-is/gitea-lab/README.md).

## Files in this folder
| File | What it is |
|---|---|
| `lab/up.sh`, `lab/down.sh` | Start/remove the runtime lab: web-01, flagd, model, copilot-1/2, lb |
| `lab/traffic.sh`, `lab/traffic/traffic.py` | 20 requests/s, half `/ask`, half `/lessons/7/notes`, for 1000 users |
| `lab/flags/flags.yaml` | The flag file Friday's deploy shipped with: `copilot-answers` on, `lesson-notes-v2` off |
| `lab/flags/rollout-check.py` | Asks Copilot about all 1000 users and compares with a saved run (stickiness) |
| `lab/copilot/` | Course Copilot with OpenFeature + flagd provider, and tests for both paths of every flag |
| `lab/model/` | Lab stand-in for the AI model service, with a switch to break it |
| `lab/nginx/default.conf`, `lab/image/Dockerfile` | Load balancer config; the web-01 image |
| `cleanup/flags/flags.yaml`, `removed.txt`, `flag-check.py` | The team's flag inventory and the CI check |
| `cleanup/prep-notify-v2.sh` | Off-screen prep: finishes notify v2 behind `NOTIFY_V2` and turns it on |
| `cleanup/remove-notify-v2.sh` | Priya's removal of `NOTIFY_V2` as a script (misses one word, like the video) |
| `.github/workflows/flags.yml` | The `flags` CI job |

## Follow along

### Part 1: release a feature with flags

1. **Start the lab and look around.**
   ```bash
   cd $L/lab
   bash up.sh
   docker exec -it -u asha -w /etc/flagd web-01 bash
   ```
   On web-01:
   ```bash
   cat flags.yaml
   curl -s copilot-1:8000/health; echo
   ```
   `copilot-answers`: ops flag, owner asha, default `on`. `lesson-notes-v2`: release flag, owner priya, default `off`,
   expires 2026-12-31. In the code (`lab/copilot/app/main.py`), `/ask` uses the model when `copilot-answers` is on and
   the course index otherwise; `/lessons/<n>/notes` passes the user ID and role as the context and asks for
   `lesson-notes-v2` with code default `False`.

2. **Friday: deployed dark.** In a second terminal on your laptop, start traffic for the whole rollout:
   `bash traffic.sh d-rollout 150`. Then on web-01:
   ```bash
   curl -s 'lb/lessons/7/notes?user=u0001&role=staff'; echo
   curl -s 'lb/lessons/7/notes?user=u0500&role=student'; echo
   ```
   Both `"notes":"v1"`.

3. **Monday: staff first.** `nano flags.yaml` and give `lesson-notes-v2` a targeting rule, between
   `defaultVariant: "off"` and `metadata:`:
   ```yaml
       targeting:
         if:
           - in: [{var: role}, [staff]]
           - "on"
   ```
   ```bash
   git diff
   git commit -qam 'lesson-notes-v2: on for staff'
   curl -s 'lb/lessons/7/notes?user=u0001&role=staff'; echo
   curl -s 'lb/lessons/7/notes?user=u0500&role=student'; echo
   ```
   Staff gets `v2`, the student still `v1`. No restart, no deploy: flagd watches the file.

4. **Wednesday: beta testers.** Change `[staff]` to `[staff, beta]`:
   ```bash
   git diff --word-diff
   git commit -qam 'lesson-notes-v2: staff and beta testers'
   curl -s 'lb/lessons/7/notes?user=u0010&role=beta'; echo
   ```

5. **10% of students, sticky.** Add one line after `- "on"` (anyone the first rule doesn't match falls through):
   ```yaml
           - fractional: [["on", 10], ["off", 90]]
   ```
   ```bash
   git commit -qam 'lesson-notes-v2: 10% of students'
   python3 ~/rollout-check.py ~/ten-a.json
   python3 ~/rollout-check.py ~/ten-b.json ~/ten-a.json
   ```
   ```
   1000 users: v2 115, v1 885
     staff 5/5 · beta 20/20 · student 90/975
   vs /home/asha/ten-b.json... kept v2 115, lost v2 0, new v2 0
   ```
   Every user got the same answer twice.

6. **50%.** Change `10` / `90` to `50` / `50`:
   ```bash
   git commit -qam 'lesson-notes-v2: 50% of students'
   python3 ~/rollout-check.py ~/fifty.json ~/ten-b.json
   curl -s copilot-1:8000/health; echo
   git log --format='%h %ad %s' --date=format:%H:%M:%S
   ```
   About 489 users get v2 (464 students), and `kept v2 115, lost v2 0, new v2 374`: nobody lost it. The health output
   shows the replicas were never restarted. When the traffic run ends, `runs/d-rollout.csv` has one row per request:
   the v2 share follows the rules (0 -> about 5% -> 13% -> 48%), and errors stay at zero.

### Part 2: the kill switch

7. **Break the model (staged).** On your laptop: `bash traffic.sh f-kill 110`. On web-01, about 15 s in:
   ```bash
   curl -s -X POST model:9000/mode -d broken; echo
   for i in 1 2 3 4; do curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' 'lb/ask?q=docker&user=u0042'; done
   ```
   `502`, four times; the first one waited 2 s (Copilot's timeout). Half the model's requests hang, half fail with 503.

8. **Flip the kill switch.** In `flags.yaml`, `copilot-answers` -> `defaultVariant: "off"`:
   ```bash
   git diff
   git commit -qam 'copilot-answers: off, the model is failing'
   curl -s 'lb/ask?q=docker&user=u0042'; echo
   ```
   `{"answer":"Try the DevOps course.","source":"fallback",...}`: errors stop within a second, latency drops to a few
   ms. Later, heal the model and turn the flag back on:
   ```bash
   curl -s -X POST model:9000/mode -d ok; echo
   # flags.yaml: copilot-answers back to defaultVariant: "on"
   git commit -qam 'copilot-answers: back on, the model is healthy'
   git log --format='%h %ad %an  %s' --date=format:%H:%M:%S -4
   ```

9. **What if flagd itself is down?** Start an in-process replica too (laptop):
   ```bash
   docker run -d --label course=devops --name copilot-3 --hostname copilot-3 --network flags-lab --network-alias copilot-3 \
     -e FLAGD_HOST=flagd -e FLAGD_RESOLVER=in-process -e FLAGD_PORT=8015 -e MODEL_URL=http://model:9000/answer flags-copilot
   docker stop flagd
   ```
   On web-01:
   ```bash
   curl -s -w ' %{time_total}s\n' 'lb/lessons/7/notes?user=u0001&role=staff'
   curl -s -w ' %{time_total}s\n' 'lb/ask?q=docker&user=u0001'
   curl -s -w ' %{time_total}s\n' 'copilot-3:8000/lessons/7/notes?user=u0001&role=staff'
   ```
   Nothing crashes. Staff gets `v1` after about 0.5 s (the provider's 500 ms deadline, then the code default `False`);
   `/ask` still uses the model (its default is `True`); the in-process copilot-3 answers `v2` from the last rules it
   synced, in about 40 ms. `docker start flagd` and the providers reconnect on their own. Choose defaults on purpose:
   a release flag defaults to off, a kill switch to the normal path.

10. **Test both paths.** Copilot's tests use OpenFeature's in-memory provider (no flagd needed):
    ```bash
    docker build -q --label course=devops --target test -t flags-copilot-test copilot
    docker run --rm flags-copilot-test
    ```
    `5 passed`: model path, fallback, notes v2, notes v1, and no flags at all (the code defaults).

### Part 3: flags are debt (CI)

11. **Prep (off screen in the video): notify v2 finished and turned on, weeks ago.** In your repo:
    ```bash
    cd ~/allcsvideos-ops && git pull
    bash $L/cleanup/prep-notify-v2.sh
    git push
    ```

12. **The flag inventory and the check.**
    ```bash
    mkdir -p flags
    cp $L/cleanup/flags/* flags/
    cp $L/.github/workflows/flags.yml .github/workflows/
    python3 flags/flag-check.py flags/flags.yaml flags/removed.txt; echo "exit code $?"
    ```
    (Needs PyYAML locally: `python3 -m pip install pyyaml==6.0.3`.) You should see:
    ```
      ok       copilot-answers  ops      owner asha
      ok       lesson-notes-v2  release  owner priya  expires 2026-12-31
      EXPIRED  notify-v2        release  owner priya  expired 2026-10-15
    FAIL: 1 problem
    ```
    ```bash
    git add flags .github && git commit -m 'flags: owners and expiry dates, checked in CI' && git push
    ```
    The `flags` job fails with the same message: the expiry date is enforced now. (If you are past 2026-12-31,
    `lesson-notes-v2` shows as expired too: that is the check doing its job.)

13. **Priya removes the flag (staged: misses one word).** v2 has been on for weeks, so the `if` and the old path go:
    ```bash
    bash $L/cleanup/remove-notify-v2.sh
    git diff --stat
    git diff hc/bin/hc
    git commit -am 'notify: remove NOTIFY_V2, v2 is the only path' && git push
    ```
    Red, twice: the hc tests fail (`missing setting NOTIFY_V2`) and flag-check says
    `REMOVED  NOTIFY_V2 is still referenced: hc/lib/checks.sh:7:...` (the list of known settings). Fix it:
    ```bash
    perl -pi -e 's/ NOTIFY_V2//' hc/lib/checks.sh
    git diff
    python3 flags/flag-check.py flags/flags.yaml flags/removed.txt
    bash hc/tests/run.sh | tail -1
    git commit -am 'checks: forget NOTIFY_V2' && git push
    git grep -c NOTIFY_V2; git log --oneline -3
    ```
    `gone NOTIFY_V2 (no references left)`, `PASS`, and the hc tests pass. Green. `removed.txt` makes sure it never
    quietly comes back.

## Common mistakes
- **Long-lived release flags.** Give each an expiry date and let CI enforce it.
- **Flags without a safe default.** A release flag defaulting to on would show unfinished work to everyone when the
  flag service is down.
- **Nested flags.** A flag that matters only when another is on hides combinations nobody tests (10 flags = 1024).
- **Flags as config or secrets.** Timeouts, URLs and API keys don't belong in a flag service; in-process providers copy
  the whole flag file into every app.
- **No audit log.** flagd's log only says the file changed. Keep flags in Git, or use a service with an audit trail.
- **Reusing a flag for a new meaning** (Knight Capital, 2012, from the SEC's order: a repurposed flag woke dead code on
  one of eight servers; over $460 million lost in about 45 minutes).

## Clean up
```bash
cd $L/lab
bash down.sh
rm -rf runs
```
Keep the `flags/` folder and `flags.yml` in `allcsvideos-ops` if you like; they are part of the team's repo now.

## Next
[M09-L04 · Versioning and Rollback](../m09-l04-versioning-and-rollback/)
