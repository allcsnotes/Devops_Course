#!/usr/bin/env bash
# Deletes the Module 10 network built in M10-L03 (VPC, subnets, gateways, route tables, security groups).
# Run it only AFTER the clean up of lessons 4, 5 and 6 (servers, load balancer, database, ECS),
# otherwise AWS refuses with DependencyViolation.
# Usage (in CloudShell, from this folder):  bash cleanup.sh
set -u
cd "$(dirname "$0")"
source ./find-ids.sh

# 1. NAT gateway (the part that costs money) - delete and wait until it is gone
if [ "$NAT" != "None" ]; then
  aws ec2 delete-nat-gateway --nat-gateway-id "$NAT" >/dev/null
  echo "waiting for $NAT to be deleted (1-2 minutes)..."
  aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT"
fi

# 2. release the Elastic IP (bills ~US$0.005/hour while it exists)
[ "$EIP" != "None" ] && aws ec2 release-address --allocation-id "$EIP"

# 3. security groups (db references web, web references alb, so delete in that order)
for sg in "$SGDB" "$SGWEB" "$SGALB"; do
  [ "$sg" != "None" ] && aws ec2 delete-security-group --group-id "$sg"
done

# 4. subnets (this also removes their route table associations)
for s in "$PUBA" "$PUBB" "$APPA" "$APPB" "$DATAA" "$DATAB"; do
  [ "$s" != "None" ] && aws ec2 delete-subnet --subnet-id "$s"
done

# 5. our three route tables
for rt in "$RTPUB" "$RTAPP" "$RTDATA"; do
  [ "$rt" != "None" ] && aws ec2 delete-route-table --route-table-id "$rt"
done

# 6. internet gateway: detach, then delete
if [ "$IGW" != "None" ]; then
  aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC"
  aws ec2 delete-internet-gateway --internet-gateway-id "$IGW"
fi

# 7. the VPC itself
[ "$VPC" != "None" ] && aws ec2 delete-vpc --vpc-id "$VPC" && echo "deleted $VPC"
