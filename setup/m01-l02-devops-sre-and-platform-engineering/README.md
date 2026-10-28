# M01-L02 · DevOps, SRE and Platform Engineering
> Video: Module 1, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- What a DevOps engineer, an SRE and a platform engineer each focus on, and where the roles overlap.
- SRE basics: SLOs, error budgets, blameless postmortems and fighting toil.
- What a golden path is, and why a platform is a product with developers as its customers.
- What a normal day looks like in each role.
- How this course maps onto the three roles, and how careers and certifications fit in.

## Before you start
Nothing to install. This is a concept lesson. It builds on [M01-L01](../m01-l01-what-is-devops/) (the dev/ops wall and the DORA metrics).

## Key ideas

**Three jobs around one change.** Every change needs someone to get it out, someone to keep it up, and someone to make both easy for everyone.

| Role | Centre of the job | Day to day | Judged by |
|---|---|---|---|
| DevOps engineer | The path from commit to production | CI/CD pipelines, infrastructure as code (Terraform), containers, cloud accounts, secrets, staging and production environments | Delivery flow, e.g. the DORA metrics |
| Site reliability engineer (SRE) | Keeping the service up, and measuring how up it is | SLOs, error budgets, on-call, incidents, blameless postmortems, removing toil | Reliability against agreed targets |
| Platform engineer | Self-service tools for developers | Golden paths, templates, docs, office hours, measuring adoption | Whether teams actually use the platform |

The edges overlap a lot: all three write code, automate and use the same tools. Titles are messy. In a ten-person startup one engineer wears all three hats. Read the job description, not the title.

**SRE in a few lines**
- Created at Google. Founder Ben Treynor Sloss: SRE is what happens when you ask a software engineer to design an operations team.
- **SLO** (service level objective): a reliability target agreed with the business. The gap between perfect and the target is the **error budget**. Budget left: ship. Budget gone: slow down and fix reliability. Module 17 builds this.
- Carries the pager, leads incidents, writes blameless postmortems.
- Fights **toil** (manual, repetitive work). Google caps ops work for its SREs at 50% of their time.
- Google's SRE workbook: `class SRE implements interface DevOps`. DevOps is the idea, SRE is one concrete way to build it.

**Platform engineering**
- The **golden path** (term made popular by Spotify): the opinionated and supported path to build something. Opinionated = sensible defaults already chosen. Supported = stay on it and the platform team helps when it breaks. You may leave it, you just lose that support.
- The platform is a product and developers are its customers. If nobody uses it, it has failed.

**Neighbours you'll work with:** developers (write features, and in a DevOps culture own their code in production), cloud engineers (accounts, networks, managed services, cost), release engineers (build, versioning and release, common for mobile apps, games and installed software).

**Everyone on one loop: code, build, test, release, run, observe**

| Stage(s) | Main owner |
|---|---|
| Code, test | Developers |
| Build, release | Release engineers |
| The pipeline from build to running in production | DevOps engineers |
| The ground it runs on | Cloud engineers |
| Run, observe (and feeding back into code) | SREs |
| The whole loop as a paved road | Platform team |

**A day in each role (from the video)**
- Asha, DevOps engineer: standup, a red main-branch build, a flaky test quarantined, a pull-request review checking a new setting reaches staging and production, Terraform for a staging Redis cache (reading the plan carefully), automating a manual deploy step. Mostly reading logs, YAML and other people's code.
- Rahul, SRE on call: SLO dashboard and error budget, a blameless postmortem (action item: a canary step), a production readiness review for Course Copilot (health checks, dashboards, alerts, runbook), automating a manual TLS certificate renewal, a page traced to a slow database query.
- Platform engineer: interviews developers, builds a new-service template. Priya fills in a short form (name, language, owning team) and gets a repo with a Dockerfile, pipeline, deploy config, dashboard and default alerts, reaching staging the same day.

**How this course maps to the roles**

| Modules | Topic | Who it is core for |
|---|---|---|
| 2-5 | Linux, shell scripting, networking, Git | Everyone |
| 6-7 | Docker and containers | Everyone |
| 8-12 | CI/CD, AWS, Terraform, Ansible | DevOps (core), platform (needed), SRE (useful) |
| 13-15 | Kubernetes, Helm, GitOps | Platform and most DevOps roles |
| 16-17 | Observability and SRE practices | SRE |
| 18 | Security | Everyone |
| 19 | Internal platforms and cost | Platform engineers |

**Career path.** People arrive from development, system administration or support, or straight from college. The ladder is similar in all three roles: junior (well-defined tasks with guidance), mid-level (owns something end to end), senior (designs systems, leads incidents, mentors), then staff (technical direction across teams) or lead/manager (grows the team). What moves you up is scope, from a task to a system to many teams.

**Certifications** (names checked against official sites in October 2026): CKA and CKAD from the Linux Foundation (hands-on, two hours in a terminal); AWS Solutions Architect Associate, CloudOps Engineer Associate (called SysOps Administrator until 2025) and DevOps Engineer Professional; HashiCorp Terraform Associate. A certification can get your CV past a filter, it cannot replace explaining a real incident or a pipeline you built. Salaries change fast and vary by city and company, so check a current, dated source for your market.

**Interview answer: DevOps vs SRE.** DevOps is a culture of shared ownership between dev and ops; SRE is one concrete way to practise it, with SLOs, error budgets and engineering that cuts toil; and platform engineering packages those practices into self-service golden paths.

## Common mistakes
- Thinking SRE just means being on call. The real work is engineering away the reasons for pages.
- Renaming the ops team to SRE. Without SLOs, error budgets and protected engineering time, it is the same team with a new title.
- Building a platform nobody asked for. A platform team that never talks to its developers builds a golden path nobody walks.
- Chasing tool lists. Popular tools change every few years. Linux, networking and good debugging habits don't.

## Try it yourself
1. Find three real job posts: one DevOps engineer, one SRE, one platform engineer. For each, mark which duties are about getting changes out, keeping things up, or making both self-service.
2. Write your own one-sentence answer to "What's the difference between DevOps and SRE?" without looking, then compare it with the one above.

## Next
[M01-L03 · Setting Up Your DevOps Lab](../m01-l03-setting-up-your-devops-lab/)
