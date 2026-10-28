# Rollout plan: the first API release with canaries (API 2.6.0)

Owner: Asha (release lead). Approver: Rahul. Date: the first Tuesday after ADR 0007 is accepted, 10:00 IST.

## Scope

Replace the API Deployment with an Argo Rollouts Rollout in staging, then production,
and ship API 2.6.0 through it. Out of scope: the storefront, Course Copilot, the database.

## Preconditions

* ADR 0007 accepted after the staging drill in its Confirmation section passed.
* Argo Rollouts installed by Argo CD in both clusters, version pinned in the GitOps repo.
* AnalysisTemplate `api-slo` merged and dry-run against last week's metrics: it would have passed every good release.
* API 2.6.0 has no schema change (checked in its pull request).
* The on-call engineer knows the release window, and the status page has a draft message ready.

## Rollout steps

1. Staging: merge the pull request that converts the Deployment to a Rollout with the same pod template (no version change). Verify that Argo CD shows Synced and Healthy and the pod count is unchanged.
2. Staging: ship 2.6.0. Watch every step's analysis run pass. Record the time each step took.
3. Staging: ship a build of 2.6.0 with an injected 10% error rate (lab flag). Confirm the analysis aborts at step 1 and all pods are back on stable.
4. Production: merge the Deployment-to-Rollout conversion at 10:00 IST, outside the evening peak. Verify Synced and Healthy.
5. Production: merge the 2.6.0 digest bump. Watch steps 10%, 25%, 50% and their analysis runs; the release lead posts each result in the release channel.
6. Production: after 100%, watch the burn-rate panels for 30 minutes before closing the release. (With replica-based canaries the old ReplicaSet is scaled down as the canary grows, so a rollback after 100% is a new rollout of the previous digest.)
7. Write the release review: times per step, any inconclusive analysis, and whether the thresholds need tuning.

## Go / no-go criteria

* Canary 5xx ratio under 0.5% over each 5-minute step (more than 0.5% aborts).
* Canary p99 latency under 250 ms over each step (250 ms or more aborts).
* At least 50 canary requests per step, or the step pauses for a person.
* No page from the burn-rate alerts (14.4x over 1 hour, 6x over 6 hours) during the release.
* Error budget remaining above 25% before starting; below 25%, only fixes ship.

## Rollback

* Automatic: a failed analysis aborts the Rollout and moves 100% back to the stable ReplicaSet. Target: all traffic on stable within 5 minutes of the failed measurement.
* Manual, during the release: `kubectl argo rollouts abort api -n allcs`, then revert the digest bump in the GitOps repo so Git matches the cluster. Target: 5 minutes.
* After 100%: revert the digest bump in the GitOps repo; the previous image is still cached on the nodes. In an emergency, skip the remaining canary steps with `kubectl argo rollouts promote --full api -n allcs`. Target: 10 minutes.
* If the Rollout controller itself misbehaves: revert the conversion pull request; Argo CD restores the plain Deployment. Target: 15 minutes.

## Communication

* Before: a note in the release channel the day before, and to support (Meera's team) with the window.
* During: the release lead posts each step's result; the on-call engineer is told before production step 5.
* On abort: the release lead posts within 5 minutes; a status page update only if users were affected for more than 5 minutes.
* After: the release review in the next platform sync, and the thresholds updated by pull request if needed.
