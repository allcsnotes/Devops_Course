# M21-L01 · How DevOps Interviews Work
> Video: Module 21, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- What DevOps, SRE, platform and cloud engineer interviews focus on, and why the job description matters more than the title
- The rounds you are likely to meet, and what each one actually tests
- Which modules of this course prepare you for which round
- A nine-step framework for scenario questions ("the site is down, what do you do?")
- How to say your answer: think aloud, state assumptions, give trade-offs, and tell STAR stories with a number

## Key ideas

### Roles and what they ask about
| Role | Builds / owns | Expect questions on |
|---|---|---|
| DevOps engineer | The path from commit to production | Pipelines, containers, infrastructure as code, cloud; often a hands-on task |
| SRE | Reliable production | Troubleshooting, incidents, SLOs, deep Linux and networking; sometimes coding |
| Platform engineer | Self-service tools for developers | Kubernetes, platform design, developers as customers |
| Cloud engineer | The cloud itself | Networks, IAM, managed services, cost (AWS, Azure or Google Cloud) |

Titles overlap, so read the job description: its tool list tells you what the technical rounds cover.
Small startups tend to run fewer, broader rounds and one long practical; large companies run a structured loop where
each interviewer scores one area against a rubric. These are patterns, not rules - ask the recruiter what the rounds are.

### The rounds
| # | Round | What it tests | Course modules that prepare you |
|---|---|---|---|
| 1 | Recruiter screen | Fit, background, logistics. Have a two-minute story of what you built | - |
| 2 | Technical screen | Solid basics, short precise answers (exit code 137? why do some users still hit the old server after a DNS change?) | M02-M06: Linux, scripting, networking, Git, containers |
| 3 | Hands-on task (live or take-home) | Can you actually do it. Reviewers read your README, tests and trade-offs | M07-M15: Docker, pipelines, Terraform, Ansible, Kubernetes |
| 4 | System / infrastructure design | Requirements first, then layers and trade-offs | Cloud, IaC, Kubernetes, security, and above all [M20-L01](../../capstones/m20-l01-designing-a-production-delivery-platform/) |
| 5 | Troubleshooting (scenario) | Your method | Networking, Kubernetes, observability, [M20-B03 troubleshooting labs](../../capstones/m20-b03-troubleshooting-labs/) |
| 6 | Behavioural | Ownership, working with people under pressure | M17 incidents, postmortems, game day; M18 and M19 stories |
| 7 | On-call / incident simulation (sometimes) | Talking through a live or role-played incident minute by minute | M17 |

The screen checks that you know the tools; every later round checks how you use them.
In the course itself, 90 of the first 94 lessons ended with an interview question from Rahul, and four of them were
already "walk me through" scenarios (site down, a request to a service name, a pod in CrashLoopBackOff, a 2 a.m. page).

### The nine-step scenario framework
| Phase | Step | What you say |
|---|---|---|
| Understand | 1. Clarify | Down for whom, since when, what changed? Two or three questions, then move on |
| | 2. Impact and severity | How many users, which features, is the SLO burning? Sets severity and who you call |
| Investigate | 3. Observe | Symptoms first: error rate and latency, then logs, then traces |
| | 4. Hypothesize by layers | DNS, network, load balancer, app, dependencies, infrastructure. Which layer explains every symptom? |
| | 5. Test the cheapest hypothesis | A read-only check that rules out the most. Change nothing yet |
| Resolve | 6. Mitigate | If a change lines up with the start, roll it back - this step can jump the queue right after step 2 |
| | 7. Fix the real cause | One change at a time |
| | 8. Verify | From the user's side: errors back to baseline and staying there |
| | 9. Prevent | Blameless postmortem, an alert that would have fired sooner, a runbook, a test |

### Worked example: "the pods keep restarting" (real outputs from [M14-L06](../../k8s/m14-l06-troubleshooting-kubernetes/))
1. **Clarify:** the API, since release 2.5.0 (new image and a changed ConfigMap).
2. **Impact:** the storefront gets 502 Bad Gateway, students see an empty catalogue - high severity.
3. **Observe:** `kubectl get pods -o wide` - three API pods, none ready, 5 restarts each; storefront pods fine.
   ```
   api-7c6cc66b89-jx4b8          0/1     Running            5 (2m ago)     4m38s
   api-7c6cc66b89-x9z2h          0/1     Error              5 (2m4s ago)   4m35s
   storefront-6d64f775c8-k8wpm   1/1     Running            0              14m
   ```
   `kubectl describe pod` shows `Exit Code: 1`, and the image is the old `2.4.0` - it crashes too.
4. **Hypothesize:** not network (pods never stay up), not memory (that would be OOMKilled, exit 137). Exit 1 = the app gave
   up by itself; the old image crashes too, so something both versions share changed: the config.
5. **Test:** `kubectl logs` gives one line:
   ```
   FATAL: DATABASE_URL is not set. Refusing to start.
   ```
   `kubectl diff -f base/api-config.yaml` against the last good file in git shows the release renamed `DATABASE_URL` to `DB_URL`.
6. **Mitigate:** `kubectl rollout undo` only rolls back the pod template, not the ConfigMap. So apply the last good
   ConfigMap from git, then `kubectl rollout restart` (env vars are read only at start).
7. **Fix:** here the same change as the mitigation (often you roll back now and fix forward later).
8. **Verify:** new pods 1/1 ready, 0 restarts, storefront answers again; keep watching past the backoff window.
9. **Prevent:** the watch output is the postmortem timeline; add an alert on the storefront error rate, a "read before you
   delete" runbook, and config that rolls back with the release (hashed ConfigMap names in Kustomize, [M15-L02](../../k8s/m15-l02-kustomize/)).

### How to say it
- **Think aloud** - "I'm checking restarts first, because they tell me if it's crashing or never starting."
- **Ask two or three clarifying questions** - interviewers often hold facts back until you ask.
- **State assumptions** - "I'll assume Kubernetes with Prometheus; tell me if that's wrong."
- **Give trade-offs** - rollback is fast but drops the feature; a forward fix keeps it but takes longer.
- **Say "I don't know, and here's how I'd find out"** - a confident guess is worse.

### Behavioural round: STAR
Situation, Task, Action, Result, then what you learned. Say "I", be honest about your part, put a number in the
result, keep it to about two minutes. The video's practice stories come from course labs (the [M17-B01 game day](../../observability/m17-b01-game-day-with-slos-chaos-and-a-postmortem/)
and the staged fake key in [M18-L01](../../security/m18-l01-shift-left/)); if you use them, say they were labs - or use a real story of your own.

### Five common mistakes
1. Tool-name dropping instead of a method.
2. No clarifying questions - solving a problem nobody asked.
3. Fixing before mitigating while users keep failing.
4. No verification ("I restarted it, so it's fixed").
5. No prevention - nothing changes after the incident.

### Interview question
*The site is down. What do you do?* - Clarify who's affected and what changed, set severity from user impact, read the
symptoms in metrics, logs and traces, test hypotheses layer by layer cheapest first; if a recent change lines up, roll
it back before finding the root cause; then fix, verify from the user's side, and prevent a repeat with a postmortem,
an alert and a runbook.

## Try it yourself
1. Have a friend play Rahul and ask "the site is down, what do you do?", holding facts back until you ask. Record
   yourself, time it, and check you hit all nine steps.
2. Open the [M20-B03 troubleshooting labs](../../capstones/m20-b03-troubleshooting-labs/), let a friend pick a fault
   number, and run the nine steps out loud.
3. Write one STAR story of your own, with a number in the result, and say it in under two minutes.

Practice sheets for Linux, Git, Kubernetes and the final sheet are in [practice/](../../practice/README.md).

## Next
[M21-L02 · The 60 Most-Asked DevOps and SRE Questions](../m21-l02-the-60-most-asked-devops-and-sre-questions/)
