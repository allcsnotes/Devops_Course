# M08-L05 · Secrets and OIDC
> Video: Module 8, Lesson 5. Watch it first, then follow along here.

## What you'll learn
- Why a long-lived key is dangerous: it leaks, never expires, is hard to rotate, and is shared.
- What to do after a leak: **revoke first**, then rotate, then clean up.
- CI secrets: stored encrypted outside the repo, read with `secrets.NAME`, scoped (organization, repository,
  environment: most specific wins), masked in logs, and **not** passed to pull requests from forks.
- How far masking goes (known strings only; use `::add-mask::` for derived values) and least-privilege job tokens.
- OIDC: the job proves who it is with a signed, short-lived token, and a trust condition pinned to one repository and
  branch decides what it gets. No stored key.

## Before you start
- Your `allcsvideos-ops` repo on GitHub (from M08-L01 to L03), Git, the GitHub CLI `gh`, `jq`.
- In the commands below, `L=<path-to-this-lesson-folder>`.
- Optional, for the last part: an AWS account with the AWS CLI configured as an admin (Module 10 sets this up
  properly). What it creates is free: an IAM OIDC identity provider and an IAM role with **no** permissions. Delete
  both at the end.
- Prefer to stay offline? The video ran on the local Gitea lab
  ([`../m08-l01-what-ci-is/gitea-lab/`](../m08-l01-what-ci-is/gitea-lab/README.md)). Gitea issues no OIDC tokens, so
  the video used a lab token stand-in and Vault: see [`lab/`](lab/README.md).
- **Every key and secret value in this lesson is FAKE.** Never use a real key for these demos.

## Files in this folder
| File | What it is |
|---|---|
| `.github/workflows/secret-scan.yml` | Trivy 0.76.0 secret scan of the repo on every push and PR |
| `stages/thumbnails-leak.yml` | Staged leak: a hard-coded (fake) AWS key plus `set -x` |
| `.github/workflows/thumbnails.yml` | The fix: the key comes from repository secrets |
| `.github/workflows/secrets-demo.yml` | Demo: what masking catches, what the job token may do, fork PRs get no secrets |
| `.github/workflows/deploy-check.yml` | Can this job get an OIDC token? |
| `.github/workflows/deploy.yml` | OIDC: get an ID token, show its claims, trade it for temporary AWS credentials |
| `aws/trust-policy.json` | IAM role trust policy: GitHub's OIDC provider, audience `sts.amazonaws.com`, one repo + `main` |
| `aws/trust-policy-any-branch.json` | Staged, dangerous: a wildcard subject that lets every branch in |
| `lab/` | Optional offline version: Gitea + token stand-in + Vault 2.1.2 dev mode |

## Follow along

1. **The secret scan first.**
   ```bash
   cd ~/allcsvideos-ops && git pull
   cp $L/.github/workflows/secret-scan.yml .github/workflows/
   git add .github/workflows/secret-scan.yml
   git commit -m 'ci: a secret scan on every push'
   git push
   ```
   Green: nothing found.

2. **The hook: a pasted key (staged, fake).**
   ```bash
   cp $L/stages/thumbnails-leak.yml .github/workflows/thumbnails.yml
   git add .github/workflows/thumbnails.yml
   git commit -m 'thumbnails: upload course thumbnails to S3'
   git push
   ```
   GitHub's own **push protection** may block this push because it looks like an AWS key. That is GitHub doing its
   job; since this value is fake you may allow it via the link in the error, or just read on. If the push goes
   through, the `thumbnails` job is green and its log shows, thanks to `set -x`:
   ```
   + printf '[default]\naws_access_key_id = %s\naws_secret_access_key = %s\n' AKIA2DEMOFAKEKEY0001 fakeDEMOsecretKEYnotREAL0000demo0000000a
   ```
   and `secret-scan` goes red:
   ```
   Total: 2 (UNKNOWN: 0, LOW: 0, MEDIUM: 0, HIGH: 0, CRITICAL: 2)
   CRITICAL: AWS (aws-access-key-id)
   CRITICAL: AWS (aws-secret-access-key)
   ```
   Too late: the key is in Git history, in every clone, in a log. With a real key, **step one is to revoke it** (on AWS:
   deactivate it in IAM, Module 10) and create a new one. Deleting the line does not un-leak it.

3. **Store the new key as repository secrets** (again fake values). `gh` reads the value from stdin, so it never
   lands in your shell history or on screen:
   ```bash
   printf '%s' 'AKIA2DEMOFAKEKEY0002' | gh secret set AWS_ACCESS_KEY_ID
   printf '%s' 'fakeDEMOsecretKEYnotREAL0000demo0000000b' | gh secret set AWS_SECRET_ACCESS_KEY
   gh secret list
   ```
   (Or **Settings > Secrets and variables > Actions > New repository secret**.) The list shows names and dates, never
   values; you can only replace a value, not read it back. GitHub even encrypts the value in your browser before it
   is sent.

4. **Priya's fix: read the key from secrets.**
   ```bash
   cp $L/.github/workflows/thumbnails.yml .github/workflows/thumbnails.yml
   git diff
   git commit -am 'thumbnails: read the AWS key from repository secrets'
   git push
   ```
   Same `set -x` trace, but now:
   ```
   + printf '[default]\naws_access_key_id = %s\naws_secret_access_key = %s\n' *** ***
   ```
   and `secret-scan` is green again. The old key is still in Git history (rewriting history is Module 18), which is
   why revoking came first.

5. **How far can you trust the stars?** Add a fake demo secret and the demo workflow, then run it by hand:
   ```bash
   printf '%s' 'demo-api-key-FAKE-1234' | gh secret set DEMO_API_KEY
   cp $L/.github/workflows/secrets-demo.yml .github/workflows/
   git add .github/workflows/secrets-demo.yml
   git commit -m 'ci: secrets demo (fake value)'
   git push
   gh workflow run secrets-demo.yml
   ```
   In the video, the `masking` job printed:
   ```
   as is:      ***
   base64:     ***
   upper case: DEMO-API-KEY-FAKE-1234
   hex:        64656d6f2d6170692d6b65792d46414b452d31323334
   upper case: ***          <- after ::add-mask:: registered the derived value
   ```
   Masking looks for known strings (and some encodings). Change the value any other way and it goes out in clear, so
   register derived values with `::add-mask::` first. Never try this with a real secret.

   The `token` job: the workflow says `permissions: contents: read`, so:
   ```
   read the repository: HTTP 200
   write a file:        HTTP 403
   ```
   Set the default token to read-only (**Settings > Actions > General > Workflow permissions**) and grant more per job,
   only where needed.

6. **A pull request from a fork gets no secrets.** You need a second GitHub account (or a friend): fork the repo, change
   one word in `README.md` on a branch, push, and open a PR to your repo. The `secrets-demo` run for that PR prints
   `event pull_request, DEMO_API_KEY set false`. (On GitHub, fork PRs from first-time contributors may need you to
   click **Approve and run** first.) Never work around this with `pull_request_target`.

7. **Environments** (concept): an environment like `production` can require reviewers and allow only chosen branches;
   its secrets reach the job only after those rules pass. Module 9 builds this for real.

8. **OIDC: can this job get a token?**
   ```bash
   cp $L/.github/workflows/deploy-check.yml .github/workflows/
   git add .github/workflows/deploy-check.yml
   git commit -m 'deploy: can a job get an OIDC token?'
   git push
   ```
   On GitHub, with `permissions: id-token: write`, both `ACTIONS_ID_TOKEN_REQUEST_URL` and
   `ACTIONS_ID_TOKEN_REQUEST_TOKEN` are `<set>`. (On Gitea 28.1.0 both were `<not set>`.)

9. **OIDC for real: the token, its claims, and AWS.** Add the deploy workflow:
   ```bash
   cp $L/.github/workflows/deploy.yml .github/workflows/
   git add .github/workflows/deploy.yml
   git commit -m 'deploy: short-lived credentials via OIDC, no stored key'
   git push
   ```
   The run requests an ID token for audience `sts.amazonaws.com`, masks it with `::add-mask::` (the token itself is a
   credential), and prints its header and claims: `alg: RS256`, a `kid`, `iss: https://token.actions.githubusercontent.com`,
   `aud: sts.amazonaws.com`, the `sub`, and `exp` a few minutes after `iat`. **Copy the exact `sub` value**: for a
   job without an environment it is `repo:<owner>/<repo>:ref:refs/heads/main`; repositories created after July 15,
   2026 also carry owner and repository IDs in it. The AWS step is skipped until you set up the role.

   Optional, on AWS (free; everything below is deleted in Clean up). Put your account ID and the exact `sub` into a
   copy of the trust policy, then:
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com
   cp $L/aws/trust-policy.json /tmp/trust-policy.json      # edit: 123456789012 -> your account, the sub -> yours
   aws iam create-role --role-name gh-allcsvideos-ops-deploy \
     --assume-role-policy-document file:///tmp/trust-policy.json
   gh variable set AWS_ROLE_ARN --body "arn:aws:iam::<your-account-id>:role/gh-allcsvideos-ops-deploy"
   gh workflow run deploy.yml
   ```
   The last step trades the ID token for credentials that expire in 15 minutes and prints the assumed-role ARN
   (`...:assumed-role/gh-allcsvideos-ops-deploy/gh-<run id>`). Nothing is stored in GitHub except the role's ARN,
   which is not a secret. The role has no permissions policy, so it can do nothing else.

10. **Staged: a deploy from a branch.** Anyone who can push a branch can edit the workflow:
    ```bash
    git switch -c priya/try-deploy
    sed -i.bak 's/branches: \[main\]/branches: [main, priya\/try-deploy]/' .github/workflows/deploy.yml && rm .github/workflows/deploy.yml.bak
    git diff
    git commit -am 'deploy: try it from my branch'
    git push -u origin priya/try-deploy
    ```
    GitHub signs a perfectly valid token whose `sub` ends in `ref:refs/heads/priya/try-deploy`, and AWS refuses
    (`Not authorized to perform sts:AssumeRoleWithWebIdentity`). The workflow file was hers to change; the trust
    condition wasn't. (In the video, Vault said `error validating token: invalid subject (sub) claim`.)

    The dangerous version: `aws/trust-policy-any-branch.json` matches `repo:<owner>/allcsvideos-ops:*`. With that
    trust policy every branch, from anyone who can push one, gets the role. If you try it
    (`aws iam update-assume-role-policy --role-name gh-allcsvideos-ops-deploy --policy-document file://...`), put the
    pinned policy back right away. IAM rejects a `sub` that is only `*`, but `repo:<you>/<repo>:*` still passes.
    ```bash
    git switch main
    git push origin --delete priya/try-deploy && git branch -D priya/try-deploy
    ```

## Common mistakes
- **`set -x` near secrets.** It prints every command with its values. Masking catches registered secrets, nothing else.
- **Secrets in build args and images.** Use build secrets, never an `ARG` (Module 6 L4, Module 7 L3).
- **Broad OIDC trust.** A wildcard subject, a missing audience, a whole organization. Pin one repository and one branch,
  or better, one protected environment.
- **Long-lived personal tokens on runners.** If you must store one (lesson 4's registry token on Gitea), give it to a bot
  account with only that scope, and rotate it.
- **Not rotating after a leak.** Deleting the line or the log isn't enough. Revoke first, then clean up; rotate the rest
  on a schedule.

## Clean up
```bash
cd ~/allcsvideos-ops
git rm .github/workflows/thumbnails.yml .github/workflows/secrets-demo.yml .github/workflows/deploy-check.yml
git commit -m 'Remove the M08-L05 demo workflows' && git push
gh secret delete AWS_ACCESS_KEY_ID; gh secret delete AWS_SECRET_ACCESS_KEY; gh secret delete DEMO_API_KEY
```
If you did the AWS part:
```bash
gh variable delete AWS_ROLE_ARN
aws iam delete-role --role-name gh-allcsvideos-ops-deploy
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::<your-account-id>:oidc-provider/token.actions.githubusercontent.com
```
Delete the fork from the second account if you made one. Optional lab: `bash lab/down.sh`.

## Next
[M09-L01 · Delivery vs Deployment](../m09-l01-delivery-vs-deployment/)
