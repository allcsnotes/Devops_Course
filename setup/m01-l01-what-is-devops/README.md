# M01-L01 · What is DevOps
> Video: Module 1, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- Why the "wall" between development and operations appears: developers are measured on change, operations on stability.
- Why big, rare releases and ticket hand-offs make outages worse and slower to fix.
- A working definition of DevOps: one team owning the whole loop (plan, code, build, test, release, deploy, operate, monitor).
- The CALMS model: culture, automation, lean, measurement, sharing.
- The DORA metrics, and how to compute them for a small demo team from Git history.

## Before you start
- Git 2.28 or newer on your laptop (`git --version`), or Docker Desktop if you would rather not use your own Git.
- A terminal (macOS/Linux terminal, or Git Bash / WSL on Windows).
- No earlier lesson needed. This is the first one.

## Key ideas

**The wall of confusion.** Dev wants more change, ops wants less (most outages start with a change). Releases get slower, rarer and bigger. When a three-week batch breaks, it is hard to find which change did it and slow to undo. Knowledge lives in tickets, and the people who wrote the code are not the ones woken up at night. Code is thrown over the wall, blame is thrown back.

**DevOps** (the word took off in 2009 with Patrick Debois' DevOpsDays in Belgium) is a culture and a set of practices where development and operations work as one team, so changes reach users quickly, safely and reliably. It is not a tool and not just a job title. It is a way of working, backed by automation.

**The Friday night, the DevOps way:** a small change, pushed to Git, starts a pipeline (build, test). The test stage checks the server settings too (they are code), finds the missing payment setting and stops before production. The fix ships during the working day, and monitoring watches the error rate after the deploy, ready to roll back one small change.

**CALMS**

| Letter | Means | In practice |
|---|---|---|
| C | Culture | Shared goal: working software in production. You build it, you run it. Blameless postmortems. |
| A | Automation | Builds, tests, deploys and servers are created by code, not by hand. |
| L | Lean | Small batches, limited work in progress, remove waiting (like a release ticket stuck in a queue). |
| M | Measurement | Measure delivery and user experience, not how busy people look. |
| S | Sharing | Share code, dashboards, on-call duty and lessons learned. |

Only one letter is about tools.

**DORA metrics** (research program since 2014, now run by Google Cloud)

| Metric | Question it answers | Group |
|---|---|---|
| Deployment frequency | How often do you deploy to production? | Throughput |
| Lead time for changes | How long from commit to production? | Throughput |
| Failed deployment recovery time (was "time to restore service") | How long to recover from a failed deployment? | Throughput |
| Change failure rate | What share of deployments need immediate intervention (rollback, hotfix)? | Instability |
| Deployment rework rate (added 2024) | What share of deployments were unplanned, caused by a production incident? | Instability |

The big finding: speed and stability are not trade-offs. Teams that do well on one tend to do well on the other.

## Files in this folder
| File | What it is |
|---|---|
| `make-demo.sh` | Builds a tiny demo Git repo `allcsvideos-web` with a made-up week: 6 commits, one `deploy-N` tag per deploy (tag date = deploy time, tag message = result). |
| `metrics.sh` | Computes lead time for every deploy and the recovery time, straight from that repo. |

## Follow along
1. Build the demo repo (the history is made up on purpose, so everyone gets the same numbers):
   ```bash
   cd setup/m01-l01-what-is-devops
   sh make-demo.sh
   cd allcsvideos-web
   git log --oneline --decorate
   ```
   You should see six commits, each with a tag (your commit IDs will differ):
   ```
   ... (HEAD -> main, tag: deploy-6) Faster video player start
   ... (tag: deploy-5) Fix checkout page, add test
   ... (tag: deploy-4) Revert New checkout page
   ... (tag: deploy-3) New checkout page
   ... (tag: deploy-2) Show lesson length on cards
   ... (tag: deploy-1) Add course search box
   ```
2. Deployment frequency: count the deploy tags.
   ```bash
   git tag -l 'deploy-*' | wc -l
   ```
   You should see `6` (on a Mac it is printed with leading spaces).
3. List every deploy with its time and result:
   ```bash
   git for-each-ref refs/tags --format='%(taggerdate:format:%a %H:%M)  %(subject)'
   ```
   ```
   Mon 10:41  ok: Add course search box
   Tue 11:33  ok: Show lesson length on cards
   Wed 15:48  FAILED: checkout errors
   Wed 16:09  ok: rollback
   Thu 12:31  ok: Fix checkout page, add test
   Fri 10:30  ok: Faster video player start
   ```
4. When was the failed change committed?
   ```bash
   git log -1 --format='%ad  %s' --date=format:'%a %H:%M' deploy-3
   ```
   ```
   Wed 15:20  New checkout page
   ```
   Committed 15:20, deployed 15:48: a lead time of 28 minutes.
5. Do the same for every deploy:
   ```bash
   cd ..
   sh metrics.sh
   ```
   ```
   deploy-1 lead_min=29 commit=Mon 10:12 deploy=Mon 10:41 ok: Add course search box
   deploy-2 lead_min=28 commit=Tue 11:05 deploy=Tue 11:33 ok: Show lesson length on cards
   deploy-3 lead_min=28 commit=Wed 15:20 deploy=Wed 15:48 FAILED: checkout errors
   deploy-4 lead_min=7 commit=Wed 16:02 deploy=Wed 16:09 ok: rollback
   deploy-5 lead_min=31 commit=Thu 12:00 deploy=Thu 12:31 ok: Fix checkout page, add test
   deploy-6 lead_min=26 commit=Fri 10:04 deploy=Fri 10:30 ok: Faster video player start
   recovery_min=21
   ```
6. Read the week's numbers:

   | Metric | This week |
   |---|---|
   | Deployment frequency | 6 deploys |
   | Lead time (median) | 28 minutes |
   | Change failure rate | 1 in 6, about 17% |
   | Recovery time | 21 minutes (failed at 15:48, rollback out at 16:09) |
   | Rework rate | 1 in 6 (the rollback was unplanned work caused by an incident) |

   Real teams pull these numbers from their pipeline and incident tools over months, and compare a team with its own past, not with other teams.

No Git on your laptop? Run the same two scripts in a throwaway container instead:
```bash
docker run --rm -v "$PWD:/work" -w /work --entrypoint sh alpine/git:v2.49.1 \
  -c 'sh make-demo.sh && sh metrics.sh'
```

## Try it yourself
1. Open `make-demo.sh` and make the Wednesday rollback go out at 16:30 instead of 16:09. Delete the repo, rebuild it, and check that `recovery_min` changes.
2. Add a seventh deploy that fails. What is the change failure rate now?

## Common mistakes
- Renaming the ops team to "the DevOps team". If it still takes tickets thrown over a wall, nothing has changed.
- Buying tools first. A pipeline tool cannot fix a culture of blame or three-week batches.
- Turning metrics into targets. Ordered to deploy more often, a team may split work into meaningless deploys. Use the metrics to find bottlenecks, not to rank people.
- Speed without safety nets. Deploying more often only helps when tests, monitoring and a fast rollback come with it.

## Clean up
```bash
rm -rf allcsvideos-web
```

## Next
[M01-L02 · DevOps, SRE and Platform Engineering](../m01-l02-devops-sre-and-platform-engineering/)
