# M10-L06 · Serverless and Managed Containers
> Video: Module 10, Lesson 6. Watch it first, then follow along here.

## What you'll learn
- The compute spectrum: EC2 -> ECS/EKS on EC2 -> Fargate -> Lambda (AWS manages more, you control less)
- Lambda: events, handler, runtime, execution role, pricing, cold starts and hard limits (15 min, 10,240 MB, 6 MB payload)
- Why `create-function` needs **`iam:PassRole`**, and reading that denial
- ECS words: **cluster, task definition, task, service**; the EC2 launch type with a container instance; dynamic host ports in bridge mode
- Where Fargate fits (awsvpc mode, per-task pricing) and ECS vs EKS
- Protecting your wallet: a **billing alarm**, AWS Budgets, tags, deleting idle resources, Cost Explorer

## Before you start
- AWS CloudShell in **us-east-1** with this repo cloned.
- The network from [M10-L03](../m10-l03-vpc-networking/) (subnet `app-a`, security group `allcs-web`) and the `ecsInstanceRole` role from [M10-L02](../m10-l02-iam/). Reload variables if needed:
  ```bash
  cd Devops_Course/cloud/m10-l03-vpc-networking && source helpers.sh && source find-ids.sh && cd ../m10-l06-serverless-and-managed-containers
  ```
  If you deleted `ecsInstanceRole`, recreate it: `aws iam create-role --role-name ecsInstanceRole --assume-role-policy-document file://../m10-l02-iam/trust-ec2.json`

> **Cost** (approx. us-east-1, check the pricing pages):
> - Lambda: free tier of 1M requests and 400,000 GB-seconds a month - this lesson costs nothing
> - ECS itself: no extra charge. The container instance is one `t3.micro`, about **US$0.0104/hour**
> - CloudWatch alarm about US$0.10/month; SNS topic free at this volume
> - plus the NAT gateway from lesson 3 (~US$0.05/hour with its IP) while it exists
>
> Run the [Clean up](#clean-up) here, then the lesson 3 clean up, when you finish Module 10.

## Files in this folder
| File | What it is |
|---|---|
| `trust-lambda.json` | trust policy: only the Lambda service may assume the role (same shape as `trust-ec2.json`) |
| `fn/app.py` | a tiny course search function (the Lambda handler) |
| `td.json` | ECS task definition `allcs-web`: nginx `1.29-alpine`, bridge mode, `hostPort: 0` |
| `cleanup.sh` | deletes everything this lesson created |

## Follow along

### Lambda
1. The execution role and its logging policy (free):
   ```bash
   aws iam create-role --role-name allcs-lambda-role --assume-role-policy-document file://trust-lambda.json --query Role.Arn --output text
   aws iam attach-role-policy --role-name allcs-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole && echo attached
   ```
   `AWSLambdaBasicExecutionRole` allows only: create a log group, create a log stream, put log events.

2. Read and zip the code:
   ```bash
   cat fn/app.py
   cd fn && zip -q ../fn.zip app.py && cd .. && ls -l fn.zip
   ```
   A ~418-byte zip is the whole deployment package.

3. Create the function (128 MB, 5 s timeout):
   ```bash
   sleep 10; aws lambda create-function --function-name allcs-search --runtime python3.13 --handler app.handler --role $(aws iam get-role --role-name allcs-lambda-role --query Role.Arn --output text) --zip-file fileb://fn.zip --memory-size 128 --timeout 5 --query "[FunctionName,Runtime,MemorySize,State]" --output text
   ```
   In the video's sandbox this was refused:
   ```
   AccessDeniedException ... is not authorized to perform: iam:PassRole on resource:
   arn:aws:iam::123456789012:role/allcs-lambda-role because no identity-based policy allows the iam:PassRole action
   ```
   An implicit deny (lesson 2): the sandbox never granted PassRole towards Lambda. In a normal admin account it succeeds with state `Pending`, then `Active`.
   *Not shown in the video:* if it worked for you, you can try it:
   ```bash
   aws lambda invoke --function-name allcs-search --cli-binary-format raw-in-base64-out --payload '{"q":"dev"}' out.json && cat out.json
   ```
   Expect status 200 with `DevOps` as the only match; the `print` line, plus START/END/REPORT lines, land in the log group `/aws/lambda/allcs-search`.

### ECS on EC2
4. Give the container instance an identity: an instance profile around `ecsInstanceRole`, plus the container-instance policy (free):
   ```bash
   aws iam create-instance-profile --instance-profile-name ecsInstanceRole --query InstanceProfile.Arn --output text
   aws iam add-role-to-instance-profile --instance-profile-name ecsInstanceRole --role-name ecsInstanceRole && echo added
   aws iam attach-role-policy --role-name ecsInstanceRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role && echo attached
   ```
   If you already created the instance profile in lesson 2, the first two commands report `EntityAlreadyExists` / `LimitExceeded`; that is fine.

5. The cluster (free) and the ECS-optimized AMI:
   ```bash
   aws ecs create-cluster --cluster-name allcs --query "cluster.[clusterName,status]" --output text
   ECSAMI=$(aws ssm get-parameter --name /aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id --query Parameter.Value --output text); echo $ECSAMI
   ```
   `allcs ACTIVE`, and an AMI ID (the video got `ami-014d96f2610438533`).

6. Launch one container instance in `app-a` (**starts billing**, t3.micro ~US$0.0104/h). The user data tells the ECS agent which cluster to join:
   ```bash
   sleep 10; ECSI=$(aws ec2 run-instances --image-id $ECSAMI --instance-type t3.micro --subnet-id $APPA --security-group-ids $SGWEB --iam-instance-profile Name=ecsInstanceRole --user-data "$(printf "#!/bin/bash\necho ECS_CLUSTER=allcs >> /etc/ecs/ecs.config\n")" --tag-specifications "$(tg instance allcs-ecs-node)" --query "Instances[0].InstanceId" --output text); echo $ECSI
   for i in $(seq 1 30); do N=$(aws ecs describe-clusters --clusters allcs --query "clusters[0].registeredContainerInstancesCount"); [ "$N" -ge 1 ] && break; sleep 10; done; echo registered=$N after $((i*10))s
   aws ecs list-container-instances --cluster allcs --query "length(containerInstanceArns)"
   ```
   `registered=1 after 40s` in the video, then `1`. (Sandbox accounts that require T-series standard credits: add `--credit-specification CpuCredits=standard`.)

7. Register the task definition and create a service with 2 tasks:
   ```bash
   cat td.json
   aws ecs register-task-definition --cli-input-json file://td.json --query "taskDefinition.[family,revision,status]" --output text
   aws ecs create-service --cluster allcs --service-name web --task-definition allcs-web --desired-count 2 --launch-type EC2 --query "service.[serviceName,desiredCount,launchType]" --output text
   time aws ecs wait services-stable --cluster allcs --services web
   aws ecs describe-services --cluster allcs --services web --query "services[0].[runningCount,desiredCount,deployments[0].rolloutState]" --output text
   ```
   You should see `allcs-web 1 ACTIVE`, `web 2 EC2`, a wait of about 31 s, then `2 2 IN_PROGRESS` (the counts match; ECS marks the rollout `COMPLETED` a little later).

8. See the dynamic host ports:
   ```bash
   aws ecs describe-tasks --cluster allcs --tasks $(aws ecs list-tasks --cluster allcs --query "taskArns" --output text) --query "tasks[].[lastStatus,containers[0].networkBindings[0].hostPort]" --output table
   ```
   ```
   |  RUNNING |  32769  |
   |  RUNNING |  32768  |
   ```
   `hostPort: 0` let Docker pick free ephemeral ports, so both containers listen on 80 inside without clashing. With a load balancer, ECS registers each instance:port in the target group for you.

### Fargate
9. Try a Fargate cluster:
   ```bash
   aws ecs create-cluster --cluster-name allcs-fargate --tags key=LaunchType,value=FARGATE --query cluster.clusterName --output text
   ```
   The video's sandbox refused it with an **explicit deny in an identity-based policy** (`AWS_EKSECSWithConditions`), often a cost-governance rule. In a normal account it works; delete it with `aws ecs delete-cluster --cluster allcs-fargate`.

### Cost guardrails
10. A billing alarm: an SNS topic, then an alarm on `EstimatedCharges` > US$10 (max over 6 hours):
    ```bash
    TOPIC=$(aws sns create-topic --name allcs-billing --query TopicArn --output text); echo $TOPIC
    aws cloudwatch put-metric-alarm --alarm-name allcs-bill-over-10usd --namespace AWS/Billing --metric-name EstimatedCharges --dimensions Name=Currency,Value=USD --statistic Maximum --period 21600 --evaluation-periods 1 --threshold 10 --comparison-operator GreaterThanThreshold --alarm-actions $TOPIC && echo alarm created
    aws cloudwatch describe-alarms --alarm-names allcs-bill-over-10usd --query "MetricAlarms[0].[AlarmName,MetricName,Threshold,StateValue]" --output table
    ```
    State `INSUFFICIENT_DATA` is normal for a new alarm. Billing metrics live only in **us-east-1**, and **Receive CloudWatch Billing Alerts** must be turned on first (by the payer account in an organization). To get notified, subscribe yourself: `aws sns subscribe --topic-arn $TOPIC --protocol email --notification-endpoint you@example.com` (use your real address, then confirm the email).

11. AWS Budgets (alerts on actual **and forecast** spend):
    ```bash
    aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text)
    ```
    In the video's sandbox: `AccessDeniedException ... with an explicit deny in a service control policy`. In your own account, create a monthly budget too.

## Common mistakes
- Lambda for everything: 15-minute limit, no long-lived connections, and a hundred tiny functions to deploy and debug.
- Over-broad execution roles (e.g. `AdministratorAccess`): start from the basic execution role and add only what the function touches.
- Forgetting billing alarms: set one on day one, plus a budget where allowed.
- Untagged resources: tag everything (`Project=allcsvideos`) and activate it as a cost allocation tag.
- Assuming serverless is always cheaper: steady all-day load is often cheaper on instances or containers with a Savings Plan.

## Clean up
1. This lesson:
   ```bash
   bash cleanup.sh
   ```
   It runs: `aws ecs update-service ... --desired-count 0` and `aws ecs delete-service --force`; `aws ec2 terminate-instances` for `allcs-ecs-node` + wait; `deregister-task-definition` / `delete-task-definitions`; `aws ecs delete-cluster --cluster allcs`; detaches the policy and deletes the `ecsInstanceRole` instance profile and role; `aws lambda delete-function` and the log group (if any), then the `allcs-lambda-role`; `aws cloudwatch delete-alarms --alarm-names allcs-bill-over-10usd` and `aws sns delete-topic`. (In your own account you may want to keep the billing alarm.)
2. End of Module 10 - delete the network and its NAT gateway (make sure lessons 4 and 5 are cleaned up first):
   ```bash
   bash ../m10-l03-vpc-networking/cleanup.sh
   ```
3. Check nothing is left billing:
   ```bash
   aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId"
   aws ec2 describe-nat-gateways --filter Name=state,Values=available,pending --query "NatGateways[].NatGatewayId"
   aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerName"
   aws rds describe-db-instances --query "DBInstances[].DBInstanceIdentifier"
   ```
   All should print `[]`.

## Next
[M11-L01 · Why IaC](../../terraform/m11-l01-why-iac/)
