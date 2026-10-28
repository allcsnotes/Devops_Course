# M10-L02 · IAM
> Video: Module 10, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- How every AWS request is decided: **who** (principal), **what** (action on a resource ARN), **is it allowed** (policies)
- Identities: the root user (lock it away), IAM users and groups, roles with temporary credentials, IAM Identity Center for people
- Reading a policy: `Version`, `Statement`, `Effect`, `Action`, `Resource`, `Condition`, and wildcards
- The evaluation logic: default deny, an explicit allow is needed, an explicit deny always wins; SCPs and permission boundaries are ceilings
- Creating a role with a **trust policy** (who may assume it) and an **instance profile** for EC2
- Reading an `AccessDenied`: implicit deny (nobody allowed it) vs explicit deny (someone forbade it)

## Before you start
- An AWS account and **AWS CloudShell** in region **us-east-1** (see [M10-L01](../m10-l01-the-cloud-model/)).
- Get this folder into CloudShell: `git clone <course repo URL>` (the link is in the resources below the video), then `cd Devops_Course/cloud/m10-l02-iam`.

**Cost: free.** IAM users, roles, policies and instance profiles cost nothing.

## Files in this folder
| File | What it is |
|---|---|
| `trust-ec2.json` | Trust policy: only the EC2 service (`ec2.amazonaws.com`) may assume the role |

## Key ideas
| Kind of policy | Attached to | What it does |
|---|---|---|
| Identity-based | user, group, role | what that identity can do |
| Resource-based (bucket policy, role trust policy) | a resource | who can use it (names a `Principal`) |
| Permissions boundary | user or role | caps what it can ever get, grants nothing |
| Service control policy (SCP) | whole account in an AWS Organization | caps the account, grants nothing |

Evaluation, in order: start at **implicit deny** -> any **explicit Deny** anywhere wins -> SCPs must allow -> resource policies -> identity policies (no allow = implicit deny) -> boundary must allow -> session policies -> **Allow**.

## Follow along
1. Who am I?
   ```bash
   aws sts get-caller-identity
   aws iam get-user
   ```
   You should see (masked):
   ```
   "UserId": "AIDAEXAMPLEID0000000",
   "Account": "123456789012",
   "Arn": "arn:aws:iam::123456789012:user/kk_labs_user_xxxx"
   ```
   User IDs start with `AIDA`, role IDs with `AROA`. If you sign in through Identity Center or a role, `get-caller-identity` shows an `assumed-role` ARN and `get-user` fails - that is fine.

2. Try to create a user:
   ```bash
   aws iam create-user --user-name priya
   ```
   In the video's sandbox this was refused with an **implicit deny**:
   ```
   AccessDenied ... is not authorized to perform: iam:CreateUser ... because no identity-based policy allows the iam:CreateUser action
   ```
   In an admin account it succeeds. If it does, delete the user right away: `aws iam delete-user --user-name priya` (for people, prefer IAM Identity Center anyway).

3. List the roles that already exist:
   ```bash
   aws iam list-roles --query 'Roles[].RoleName' --output text | tr '\t' '\n' | head -30
   ```
   Most start with `AWSServiceRoleFor...`: **service-linked roles** that a service (Auto Scaling, RDS, NAT gateway...) created for itself. `OrganizationAccountAccessRole` (if present) is a cross-account role for the organization's management account.

4. Look at AWS managed policies:
   ```bash
   aws iam get-policy --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess --query Policy.DefaultVersionId

   aws iam get-policy-version --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
     --version-id $(aws iam get-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess --query Policy.DefaultVersionId --output text) \
     --query PolicyVersion.Document
   ```
   The first printed `"v190"` in the video (AWS keeps editing managed policies). The second prints:
   ```
   "Version": "2012-10-17",
   "Statement": [ { "Effect": "Allow",
       "Action": [ "s3:Get*", "s3:List*", "s3:Describe*", "s3-object-lambda:Get*", "s3-object-lambda:List*" ],
       "Resource": "*" } ]
   ```
   `s3:Get*` includes `GetObject` and `Resource: *` is every bucket: "read-only" still reads all your data.

5. Create a role for the web servers. First read the trust policy, then create the role:
   ```bash
   cat trust-ec2.json
   aws iam create-role --role-name allcs-web-role --assume-role-policy-document file://trust-ec2.json
   ```
   You should see a `RoleId` starting with `AROA`, the ARN `arn:aws:iam::123456789012:role/allcs-web-role` and the trust policy echoed back. There is **no permission policy** yet: EC2 can assume this role and do nothing with it. Trust says *who*, permissions say *what*.

6. Put a role on a server with an **instance profile** (the console does this for you; the CLI needs two commands). The video showed it for `ecsInstanceRole`, used again in lesson 6:
   ```bash
   aws iam create-role --role-name ecsInstanceRole --assume-role-policy-document file://trust-ec2.json
   aws iam create-instance-profile --instance-profile-name ecsInstanceRole --query InstanceProfile.Arn --output text
   aws iam add-role-to-instance-profile --instance-profile-name ecsInstanceRole --role-name ecsInstanceRole && echo added
   ```
   You should see `arn:aws:iam::123456789012:instance-profile/ecsInstanceRole` and `added`.

7. Reading real denials (shown in the video from lessons 1 and 6; you don't need to run them):
   - `iam:PassRole` denied when creating a Lambda function -> **implicit** deny. Handing a role to a service gives the service that role's power, so limit PassRole to specific role ARNs (and `iam:PassedToService`).
   - `ec2:DescribeAvailabilityZones --region ap-south-1` -> **explicit deny in a service control policy**. No allow in the account can fix that.
   - `ecs:CreateCluster` tagged for Fargate -> **explicit deny in an identity-based policy**.

   Rule of thumb: implicit = add one small, specific allow; explicit = someone forbade it, adding an allow never helps.

## Common mistakes
- Using root for daily work. IAM policies cannot limit root: MFA on, no access keys, work through an admin role.
- `"Action": "*"` with `"Resource": "*"`: the IAM version of `chmod 777`.
- Long-lived access keys: they leak and never expire. Prefer roles and temporary credentials (instance profiles, OIDC for CI, Identity Center for people).
- An overly broad trust policy (`"Principal": "*"`) lets anyone try to assume your role.
- Forgetting that an explicit deny wins: if an SCP or a `Deny` blocks it, no allow will fix it.

## Clean up
Free, but tidy. Lesson 6 needs `ecsInstanceRole` and its instance profile, so keep them if you continue to lesson 6 (lesson 6 also shows how to create them).
```bash
aws iam delete-role --role-name allcs-web-role

# only if you are NOT continuing to lesson 6:
aws iam remove-role-from-instance-profile --instance-profile-name ecsInstanceRole --role-name ecsInstanceRole
aws iam delete-instance-profile --instance-profile-name ecsInstanceRole
aws iam delete-role --role-name ecsInstanceRole
```

## Next
[M10-L03 · VPC Networking](../m10-l03-vpc-networking/)
