# CloudShell forgets shell variables when the session restarts.
# This finds the Module 10 network again by its Name tags and sets
# VPC, PUBA, PUBB, APPA, APPB, DATAA, DATAB, IGW, NAT, EIP, RTPUB, RTAPP, RTDATA, SGALB, SGWEB, SGDB.
# Load it with:  source find-ids.sh
# (Read-only: it creates nothing.)

VPC=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=allcsvideos-vpc \
  --query "Vpcs[0].VpcId" --output text)

_subnet() {
  aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC" Name=tag:Name,Values="$1" \
    --query "Subnets[0].SubnetId" --output text
}
PUBA=$(_subnet public-a); PUBB=$(_subnet public-b)
APPA=$(_subnet app-a);    APPB=$(_subnet app-b)
DATAA=$(_subnet data-a);  DATAB=$(_subnet data-b)

IGW=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$VPC" \
  --query "InternetGateways[0].InternetGatewayId" --output text)
NAT=$(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values="$VPC" Name=state,Values=available,pending \
  --query "NatGateways[0].NatGatewayId" --output text)
EIP=$(aws ec2 describe-addresses --filters Name=tag:Name,Values=nat-a-eip \
  --query "Addresses[0].AllocationId" --output text)

_rt() {
  aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC" Name=tag:Name,Values="$1" \
    --query "RouteTables[0].RouteTableId" --output text
}
RTPUB=$(_rt rt-public); RTAPP=$(_rt rt-app); RTDATA=$(_rt rt-data)

_sg() {
  aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" Name=group-name,Values="$1" \
    --query "SecurityGroups[0].GroupId" --output text
}
SGALB=$(_sg allcs-alb); SGWEB=$(_sg allcs-web); SGDB=$(_sg allcs-db)

echo "VPC=$VPC"
echo "PUBA=$PUBA PUBB=$PUBB APPA=$APPA APPB=$APPB DATAA=$DATAA DATAB=$DATAB"
echo "IGW=$IGW NAT=$NAT EIP=$EIP"
echo "RTPUB=$RTPUB RTAPP=$RTAPP RTDATA=$RTDATA"
echo "SGALB=$SGALB SGWEB=$SGWEB SGDB=$SGDB"
