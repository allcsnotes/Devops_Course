#!/usr/bin/env bash
# Deletes what M10-L06 created: the ECS service, cluster, container instance and task definition,
# the ecsInstanceRole instance profile and role, the Lambda function and role (if they exist),
# the billing alarm and its SNS topic.
# The network from M10-L03 stays (clean it up last with ../m10-l03-vpc-networking/cleanup.sh).
# Usage (in CloudShell, from this folder):  bash cleanup.sh
set -u

# 1. ECS service: scale to 0, then delete
aws ecs update-service --cluster allcs --service web --desired-count 0 \
  --query "service.desiredCount" --output text 2>/dev/null
aws ecs delete-service --cluster allcs --service web --force \
  --query "service.status" --output text 2>/dev/null

# 2. the container instance (EC2, t3.micro) - terminate and wait
IDS=$(aws ec2 describe-instances --filters Name=tag:Name,Values=allcs-ecs-node \
  Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$IDS" ]; then
  aws ec2 terminate-instances --instance-ids $IDS >/dev/null
  echo "waiting for $IDS to terminate..."
  aws ec2 wait instance-terminated --instance-ids $IDS
fi

# 3. task definition revisions: deregister, then delete
for td in $(aws ecs list-task-definitions --family-prefix allcs-web --query "taskDefinitionArns" --output text); do
  aws ecs deregister-task-definition --task-definition "$td" >/dev/null
  aws ecs delete-task-definitions --task-definitions "$td" >/dev/null
done

# 4. the cluster
aws ecs delete-cluster --cluster allcs --query "cluster.status" --output text 2>/dev/null

# 5. ecsInstanceRole: detach policy, empty and delete the instance profile, delete the role
aws iam detach-role-policy --role-name ecsInstanceRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role 2>/dev/null
aws iam remove-role-from-instance-profile --instance-profile-name ecsInstanceRole --role-name ecsInstanceRole 2>/dev/null
aws iam delete-instance-profile --instance-profile-name ecsInstanceRole 2>/dev/null
aws iam delete-role --role-name ecsInstanceRole 2>/dev/null

# 6. Lambda (only exists if create-function worked in your account)
aws lambda delete-function --function-name allcs-search 2>/dev/null
aws logs delete-log-group --log-group-name /aws/lambda/allcs-search 2>/dev/null
aws iam detach-role-policy --role-name allcs-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null
aws iam delete-role --role-name allcs-lambda-role 2>/dev/null

# 7. billing alarm + SNS topic (in your own account you may prefer to KEEP these)
aws cloudwatch delete-alarms --alarm-names allcs-bill-over-10usd
TOPIC=$(aws sns list-topics --query "Topics[?ends_with(TopicArn,':allcs-billing')].TopicArn" --output text)
[ -n "$TOPIC" ] && aws sns delete-topic --topic-arn "$TOPIC"
echo "M10-L06 resources deleted"
