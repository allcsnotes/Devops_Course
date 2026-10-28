#!/usr/bin/env bash
# Deletes what M10-L04 created: the Auto Scaling group (and its instances),
# the load balancer, the target group and the launch template.
# The network from M10-L03 stays (clean it up with ../m10-l03-vpc-networking/cleanup.sh).
# Usage (in CloudShell, from this folder):  bash cleanup.sh
set -u

# 1. Auto Scaling group: --force-delete also terminates its instances
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name allcs-web-asg --force-delete
IDS=$(aws ec2 describe-instances --filters Name=tag:Name,Values=allcs-web \
  Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down \
  --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$IDS" ]; then
  echo "waiting for instances to terminate: $IDS"
  aws ec2 wait instance-terminated --instance-ids $IDS
fi

# 2. load balancer (deleting it also deletes its listener), then wait
ALB=$(aws elbv2 describe-load-balancers --names allcs-alb \
  --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null)
if [ -n "$ALB" ] && [ "$ALB" != "None" ]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB"
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB"
fi

# 3. target group (only possible once no load balancer uses it)
TG=$(aws elbv2 describe-target-groups --names allcs-web-tg \
  --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null)
[ -n "$TG" ] && [ "$TG" != "None" ] && aws elbv2 delete-target-group --target-group-arn "$TG"

# 4. launch template (free, but tidy)
aws ec2 delete-launch-template --launch-template-name allcs-web \
  --query "LaunchTemplate.LaunchTemplateName" --output text
echo "M10-L04 resources deleted"
