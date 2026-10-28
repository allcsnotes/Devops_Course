# M18-L05 · Cloud Security and Compliance
> Video: Module 18, Lesson 5. Watch it first, then follow along here.

## What you'll learn
- The shared responsibility model: AWS secures the cloud, you secure what you put in it.
- An IAM audit with the credential report, account summary, password policy and access keys.
- Least privilege in four steps: last-accessed data, policy validation with Access Analyzer, the policy simulator, and ceilings (boundaries and SCPs).
- CloudTrail: 90-day Event history versus a validated, multi-region trail in a separate log-archive account; GuardDuty, Config and Security Hub.
- Policy as code for the account baseline: Checkov plus your own Rego rules with conftest. 27 failures become 0.
- Where CIS, SOC 2 and ISO 27001 fit, and turning today's findings into evidence.

## Before you start
- For the audit: an AWS account or sandbox, and AWS CloudShell (or the AWS CLI v2). The audit commands are read-only,
  except `generate-credential-report` (free).
- For policy as code: Docker Desktop. Checkov and conftest run in a small image built from `tools/Dockerfile`.
- The Module 11 Terraform stack and Checkov, and Module 10 IAM basics.
- Pinned versions: Checkov 3.3.30 (`bridgecrew/checkov:3.3.30`, by digest), conftest 0.71.1 (OPA 1.21.1, by digest);
  for the optional validate: Terraform 1.16.6 and AWS provider 6.69.1.

> **Cost and safety.** This lesson does **not** apply the Terraform baseline: in the video it was scanned and
> validated only. If you ever apply `fixes/security-v2/` in your own account, it creates billable resources: CloudTrail
> data events (USD 0.10 per 100,000), a KMS key (monthly charge), GuardDuty, AWS Config recording and rules, and
> Security Hub, in every region you enable. Remove them with `terraform destroy`.

## Files in this folder
| File | What it is |
|---|---|
| `security/audit.tf`, `security/iam.tf` | Asha's first draft of the account baseline, with real mistakes on purpose |
| `fixes/security-v2/` | The fixed baseline: `audit.tf` (trail to the log-archive bucket, multi-region, validated, KMS, data events), `iam.tf`, `boundary.tf`, `kms.tf`, `detect.tf` (GuardDuty, Access Analyzer, Security Hub CIS 5.0.0, Config) |
| `fixes/validate-versions.tf` | Provider pin used only for an offline `terraform validate` |
| `policy/iam.rego`, `policy/audit.rego`, `policy/iam_test.rego` | The team's own rules (no `*` actions, no PassRole on `*`, a boundary on every role, logs leave the account) and their unit tests |
| `iam/too-broad.json` | A deliberately bad policy: `*` on `*`, a scoped S3 statement, PassRole on every role |
| `tools/Dockerfile` | Checkov 3.3.30 + conftest 0.71.1 + jq, as user asha |

## Follow along
### Part 1: the IAM audit (AWS CloudShell)
1. Who am I, and the credential report (generate it twice: started, then complete).
   ```bash
   aws sts get-caller-identity
   aws iam generate-credential-report
   aws iam generate-credential-report
   aws iam get-credential-report --query Content --output text | base64 -d | cut -d, -f1,4,5,8,9,10,11,14,16 | column -s, -t
   ```
   In the video (account and user masked):
   ```
   user               password_enabled  password_last_used    mfa_active  access_key_1_active  access_key_1_last_rotated  access_key_1_last_used_date
   <root_account>     false             no_information        false       false                N/A                        N/A
   lab-user           true              2026-10-21T17:48:06Z  false       true                 2026-10-21T12:55:12Z       N/A
   ```
   Root without MFA, a user without MFA, and an active key that was never used.
2. Account summary, keys and the password policy.
   ```bash
   aws iam get-account-summary --query "SummaryMap.{Users:Users,Roles:Roles,Policies:Policies,MFADevices:MFADevices,AccountMFAEnabled:AccountMFAEnabled,AccountAccessKeysPresent:AccountAccessKeysPresent}"
   aws iam list-access-keys --user-name <your-user> --output table
   aws iam get-account-password-policy
   aws iam list-attached-user-policies --user-name <your-user> --output table
   ```
   ```
   "AccountMFAEnabled": 0,
   "AccountAccessKeysPresent": 0
   An error occurred (NoSuchEntity) ... The Password Policy with domain name 123456789012 cannot be found.
   ```
   In the sandbox, `list-attached-user-policies` was `AccessDenied` (the sandbox hides its own policies). A real
   auditor gets a read-only role such as the AWS managed `SecurityAudit` policy.
3. Lint a policy before it ships (free). Upload `iam/too-broad.json` to CloudShell.
   ```bash
   cat too-broad.json | jq -c .Statement[]
   aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY --policy-document file://too-broad.json --query "findings[].[findingType,issueCode,findingDetails]" --output text
   ```
   ```
   WARNING           CREATE_SLR_WITH_STAR_IN_ACTION_AND_RESOURCE   ...
   SECURITY_WARNING  PASS_ROLE_WITH_STAR_IN_ACTION_AND_RESOURCE    ...
   SECURITY_WARNING  PASS_ROLE_WITH_STAR_IN_RESOURCE               ...
   ```
   It doesn't say "star on star is full admin": deciding how much is too much is the next tools' job.
   `aws accessanalyzer check-access-not-granted ... --access actions=iam:CreateUser,iam:DeleteRole` and
   `create-analyzer` were denied in the sandbox; in a real account they answer "can this policy ever create a user?".
4. Test before you deploy: the policy simulator (nothing actually runs).
   ```bash
   aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::<account-id>:user/<your-user> --action-names iam:CreateUser iam:CreateAccessKey s3:ListAllMyBuckets ec2:RunInstances secretsmanager:GetSecretValue organizations:LeaveOrganization --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output table
   ```
   ```
   |  iam:CreateUser                  |  implicitDeny  |
   |  s3:ListAllMyBuckets             |  allowed       |
   |  organizations:LeaveOrganization |  explicitDeny  |
   ```
5. Would we even know? No trail, but Event history still has 90 days of management events.
   ```bash
   aws cloudtrail describe-trails
   aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=allcs/prod/db --max-results 20 --query 'Events[].[EventTime,EventName,Username]' --output table
   aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=PutResourcePolicy --max-results 1 --query 'Events[0].CloudTrailEvent' --output text | jq '{eventTime,eventSource,eventName,awsRegion,userIdentity:{type:.userIdentity.type,arn:.userIdentity.arn},userAgent,requestParameters,readOnly,managementEvent}'
   ```
   `"trailList": []`, then every call on the lesson 2 secret, and the refused public policy recorded in full
   (`"Principal":"*"`, `"blockPublicPolicy": true`). Use a resource name from your own account if you skipped lesson 2.
6. The detection services. In the sandbox these were blocked or not set up:
   ```bash
   aws configservice describe-configuration-recorders
   aws configservice describe-delivery-channels
   aws securityhub describe-hub
   aws guardduty list-detectors
   ```
   `"ConfigurationRecorders": []`, `"DeliveryChannels": []`, and AccessDenied for Security Hub and GuardDuty, so they
   stay diagrams in the video. GuardDuty's `InstanceCredentialExfiltration.OutsideAWS` is the Capital One pattern.

### Part 2: policy as code (Docker on your laptop)
7. Build the tools and open a shell with this folder mounted.
   ```bash
   docker build -t cloudsec-tools:1 tools
   docker run --rm -it -v "$PWD":/home/asha/allcsvideos cloudsec-tools:1 bash
   ```
8. Checkov on the first draft.
   ```bash
   cd security && ls
   checkov -d . --framework terraform --quiet -o json > /tmp/ck.json; echo "exit code: $?"
   jq -c ".summary | {passed, failed, skipped}" /tmp/ck.json
   jq -r '.results.failed_checks[] | "\((.check_id + "              ")[:14])\((.resource + "                                      ")[:38]) \(.check_name)"' /tmp/ck.json
   ```
   ```
   exit code: 1
   {"passed":26,"failed":27,"skipped":0}
   CKV_AWS_36    aws_cloudtrail.main                    Ensure CloudTrail log file validation is enabled
   CKV_AWS_67    aws_cloudtrail.main                    Ensure CloudTrail is enabled in all Regions
   CKV_AWS_10    aws_iam_account_password_policy.main   Ensure IAM password policy requires minimum length of 14 or greater
   CKV_AWS_1     aws_iam_policy_document.catalog        Ensure IAM policies that allow full "*-*" administrative privileges are not created
   ...
   ```
9. Your own rules with conftest, on the Terraform and on the plain JSON policy, plus the rules' unit tests.
   ```bash
   conftest test --no-color --parser hcl2 -p ../policy *.tf; echo "exit code: $?"
   cd ..
   conftest test --no-color -p policy iam/too-broad.json; echo "exit code: $?"
   conftest verify --no-color -p policy; echo "exit code: $?"
   ```
   ```
   WARN - audit.tf - main - aws_cloudtrail.main: not an organization trail yet
   FAIL - audit.tf - main - aws_cloudtrail.main: logs go to a bucket in this account, send them to the log-archive account
   FAIL - iam.tf - main - aws_iam_role.catalog: no permissions boundary
   FAIL - iam.tf - main - catalog: Action "*" allows every API call
   FAIL - iam.tf - main - catalog: iam:PassRole on every role
   14 tests, 9 passed, 1 warning, 4 failures, 0 exceptions
   ...
   7 tests, 5 passed, 0 warnings, 2 failures, 0 exceptions
   2 tests, 2 passed, 0 warnings, 0 failures, 0 exceptions, 0 skipped
   ```
10. The fix. Compare the files, then scan the fixed baseline.
    ```bash
    cd fixes/security-v2 && ls
    checkov -d . --framework terraform -o json > /tmp/ck.json; echo "exit code: $?"
    jq -c ".summary | {passed, failed, skipped}" /tmp/ck.json
    jq -r '.results.skipped_checks[] | "\((.check_id + "              ")[:14])\(.check_result.suppress_comment)"' /tmp/ck.json
    conftest test --no-color --parser hcl2 -p ../../policy *.tf; echo "exit code: $?"
    exit
    ```
    ```
    exit code: 0
    {"passed":66,"failed":0,"skipped":7}
    CKV_AWS_9     no forced expiry: NIST SP 800-63B, and CIS since v1.4
    CKV_AWS_109   key policy, scoped to this key
    ...
    35 tests, 34 passed, 1 warning, 0 failures, 0 exceptions
    exit code: 0
    ```
    Every skip has a written reason, reviewed like code.
11. Optional: an offline `terraform validate` of the fixed baseline (no AWS credentials needed, nothing is created).
    ```bash
    cp fixes/validate-versions.tf fixes/security-v2/
    docker run --rm -v "$PWD/fixes/security-v2":/w -w /w --entrypoint sh hashicorp/terraform:1.16.6 -c 'terraform init -backend=false -input=false >/dev/null && terraform fmt -check && terraform validate'
    rm fixes/security-v2/validate-versions.tf fixes/security-v2/.terraform.lock.hcl; rm -rf fixes/security-v2/.terraform
    ```
    `Success! The configuration is valid.`

## Remediation checklist (from the lesson)
| Area | Do |
|---|---|
| Identities | MFA on root (passkey or security key), no root keys, delete unused access keys, people sign in through IAM Identity Center |
| Logging | Organization trail into the log-archive account: multi-region, validated, encrypted, data events for the media bucket |
| Detection | GuardDuty, Security Hub with CIS, Config and an Access Analyzer in every region you use; page on high severity only |
| Least privilege | One role per service, scoped to its resources, under a boundary; review last-accessed data quarterly; SCPs |
| Code | All of it in Terraform, behind Checkov and conftest |

Frameworks: the CIS AWS Foundations Benchmark (Security Hub automates v5), SOC 2 (a CPA firm's report; Type 1 = design
at a point in time, Type 2 = it worked over a period), ISO/IEC 27001:2022 (a certified ISMS, 93 Annex A controls).
AWS Artifact gives you AWS's own reports; your side needs your own evidence.

## Common mistakes
- **Root access keys.** A key for root is root, and no policy can limit it. Never create one.
- **Long-lived user keys.** Prefer roles and temporary credentials; delete keys nobody uses.
- **Star on star.** It turns one stolen credential into a breach. Scope actions and resources.
- **Audit logs in the same account.** Whoever owns the account can delete them. Use a log-archive account, with validation.
- **Alerting on everything.** Page on high severity, ticket the rest, tune noisy rules.

## Clean up
Nothing to delete in AWS (the audit only reads). Locally: `docker image rm cloudsec-tools:1`.

## Next
[M18-B01 · A Secure Delivery Pipeline](../m18-b01-a-secure-delivery-pipeline/)
