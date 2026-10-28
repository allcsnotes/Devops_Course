# M10-L03 · VPC Networking
> Video: Module 10, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- What a VPC is: your own isolated network in one region, spanning its availability zones; each **subnet lives in one AZ**
- Why AWS gives you only **251 of 256** addresses in a /24 (five are reserved)
- The big idea: a subnet is **public, private or isolated because of its route table** (internet gateway, NAT gateway, or only the local route)
- Security groups: stateful, allow-only firewalls on instances, **chained by reference** (internet -> ALB -> web -> database)
- What costs money here (the NAT gateway and its public IP) and why production runs one NAT gateway per AZ

## Before you start
- AWS CloudShell in **us-east-1** with this repo cloned (see [M10-L02](../m10-l02-iam/)).
- The address plan comes from Module 4, Lesson 1: `10.0.0.0/16`, two zones, a public, an app and a data subnet in each.

> **Cost warning.** Most of this lesson is free (VPC, subnets, route tables, internet gateway, security groups).
> The **NAT gateway bills about US$0.045/hour plus US$0.045 per GB** processed, and its **Elastic IP about US$0.005/hour**
> (approx. us-east-1 prices, check the AWS VPC pricing page). That is roughly US$1.20 a day even with no traffic.
> If you stop for the day, run the [Clean up](#clean-up) and rebuild next time.

## Files in this folder
| File | What it is |
|---|---|
| `helpers.sh` | the two tiny helpers from the video: `tg` (tag spec) and `mk` (create one subnet) |
| `find-ids.sh` | finds the network again by Name tags after a CloudShell restart (sets `$VPC`, `$PUBA`, `$SGWEB`, ...). Read-only |
| `cleanup.sh` | deletes everything this lesson created, in the right order |

## Follow along
1. Load the helpers:
   ```bash
   cd Devops_Course/cloud/m10-l03-vpc-networking
   source helpers.sh
   tg vpc allcsvideos-vpc
   ```
   `tg` prints `ResourceType=vpc,Tags=[{Key=Name,Value=allcsvideos-vpc},{Key=Project,Value=allcsvideos}]`.

2. Create the VPC, turn on DNS hostnames, and check it (free):
   ```bash
   VPC=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications "$(tg vpc allcsvideos-vpc)" --query Vpc.VpcId --output text); echo $VPC
   aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames
   aws ec2 describe-vpcs --vpc-ids $VPC --query "Vpcs[0].[VpcId,CidrBlock,State,IsDefault]" --output table
   ```
   You should see your `vpc-...` ID, `10.0.0.0/16`, `available`, `False` (not the default VPC).

3. Create the six subnets, two per tier, one per zone (free):
   ```bash
   PUBA=$(mk public-a 10.0.101.0/24 us-east-1a); PUBB=$(mk public-b 10.0.102.0/24 us-east-1b); APPA=$(mk app-a 10.0.1.0/24 us-east-1a); APPB=$(mk app-b 10.0.2.0/24 us-east-1b); DATAA=$(mk data-a 10.0.21.0/24 us-east-1a); DATAB=$(mk data-b 10.0.22.0/24 us-east-1b); echo $PUBA $PUBB $APPA $APPB $DATAA $DATAB

   aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query "sort_by(Subnets,&CidrBlock)[].[Tags[?Key==\`Name\`]|[0].Value,CidrBlock,AvailabilityZone,AvailableIpAddressCount]" --output table
   ```
   You should see:
   ```
   |  app-a   |  10.0.1.0/24    |  us-east-1a  |  251 |
   |  public-a|  10.0.101.0/24  |  us-east-1a  |  251 |
   |  public-b|  10.0.102.0/24  |  us-east-1b  |  251 |
   |  app-b   |  10.0.2.0/24    |  us-east-1b  |  251 |
   |  data-a  |  10.0.21.0/24   |  us-east-1a  |  251 |
   |  data-b  |  10.0.22.0/24   |  us-east-1b  |  251 |
   ```
   The sort is text, not numeric (`10.0.101` before `10.0.2`). 251 = 256 minus the 5 addresses AWS reserves (.0 network, .1 router, .2 DNS, .3 future, .255 broadcast).

4. Make the public tier public: internet gateway, `rt-public` with `0.0.0.0/0 -> IGW`, associate it, auto-assign public IPs (all free):
   ```bash
   IGW=$(aws ec2 create-internet-gateway --tag-specifications "$(tg internet-gateway allcsvideos-igw)" --query InternetGateway.InternetGatewayId --output text); aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC; echo "$IGW attached to $VPC"
   RTPUB=$(aws ec2 create-route-table --vpc-id $VPC --tag-specifications "$(tg route-table rt-public)" --query RouteTable.RouteTableId --output text); echo $RTPUB
   aws ec2 create-route --route-table-id $RTPUB --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
   aws ec2 associate-route-table --route-table-id $RTPUB --subnet-id $PUBA; aws ec2 associate-route-table --route-table-id $RTPUB --subnet-id $PUBB
   for s in $PUBA $PUBB; do aws ec2 modify-subnet-attribute --subnet-id $s --map-public-ip-on-launch; done; echo public subnets give public IPs
   ```
   `create-route` answers `"Return": true`; each association shows `"State": "associated"`.

5. The NAT gateway in `public-a` (**costs money from now on**: ~US$0.045/h + ~US$0.005/h for the Elastic IP; deleted by `cleanup.sh`):
   ```bash
   EIP=$(aws ec2 allocate-address --domain vpc --tag-specifications "$(tg elastic-ip nat-a-eip)" --query AllocationId --output text); echo $EIP
   NAT=$(aws ec2 create-nat-gateway --subnet-id $PUBA --allocation-id $EIP --tag-specifications "$(tg natgateway nat-a)" --query NatGateway.NatGatewayId --output text); echo $NAT
   time aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT
   aws ec2 describe-nat-gateways --nat-gateway-ids $NAT --query "NatGateways[0].[NatGatewayId,State,SubnetId,NatGatewayAddresses[0].PublicIp]" --output table
   ```
   The wait took `real 1m46s` in the video. The table shows `available`, the `public-a` subnet ID and the NAT's public IP.

6. `rt-app` (private, out through the NAT) and `rt-data` (isolated, no route out) - free:
   ```bash
   RTAPP=$(aws ec2 create-route-table --vpc-id $VPC --tag-specifications "$(tg route-table rt-app)" --query RouteTable.RouteTableId --output text); aws ec2 create-route --route-table-id $RTAPP --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT; aws ec2 associate-route-table --route-table-id $RTAPP --subnet-id $APPA >/dev/null; aws ec2 associate-route-table --route-table-id $RTAPP --subnet-id $APPB >/dev/null; echo $RTAPP
   RTDATA=$(aws ec2 create-route-table --vpc-id $VPC --tag-specifications "$(tg route-table rt-data)" --query RouteTable.RouteTableId --output text); aws ec2 associate-route-table --route-table-id $RTDATA --subnet-id $DATAA >/dev/null; aws ec2 associate-route-table --route-table-id $RTDATA --subnet-id $DATAB >/dev/null; echo $RTDATA
   ```

7. Compare the three route tables:
   ```bash
   for rt in $RTPUB $RTAPP $RTDATA; do
     aws ec2 describe-route-tables --route-table-ids $rt --query 'RouteTables[0].Routes[].[DestinationCidrBlock,GatewayId||NatGatewayId,State]' --output table
   done
   ```
   You should see:
   ```
   rt-public:  10.0.0.0/16 local active   |  0.0.0.0/0  igw-...  active
   rt-app:     10.0.0.0/16 local active   |  0.0.0.0/0  nat-...  active
   rt-data:    10.0.0.0/16 local active
   ```
   Same kind of subnets, three route tables: public, private, isolated.

8. The security group chain (free):
   ```bash
   SGALB=$(aws ec2 create-security-group --group-name allcs-alb --description "ALB from the internet" --vpc-id $VPC --query GroupId --output text); aws ec2 authorize-security-group-ingress --group-id $SGALB --protocol tcp --port 80 --cidr 0.0.0.0/0 --query "SecurityGroupRules[0].[IpProtocol,FromPort,CidrIpv4]" --output text
   SGWEB=$(aws ec2 create-security-group --group-name allcs-web --description "web from the ALB only" --vpc-id $VPC --query GroupId --output text); aws ec2 authorize-security-group-ingress --group-id $SGWEB --protocol tcp --port 80 --source-group $SGALB --query "SecurityGroupRules[0].[IpProtocol,FromPort,ReferencedGroupInfo.GroupId]" --output text
   SGDB=$(aws ec2 create-security-group --group-name allcs-db --description "postgres from web only" --vpc-id $VPC --query GroupId --output text); aws ec2 authorize-security-group-ingress --group-id $SGDB --protocol tcp --port 5432 --source-group $SGWEB --query "SecurityGroupRules[0].[IpProtocol,FromPort,ReferencedGroupInfo.GroupId]" --output text
   aws ec2 describe-security-groups --group-ids $SGALB $SGWEB $SGDB --query "SecurityGroups[].[GroupName,GroupId,Description]" --output table
   ```
   You should see `tcp 80 0.0.0.0/0`, then `tcp 80 sg-<alb id>`, then `tcp 5432 sg-<web id>`: each tier only accepts traffic from the tier in front of it.

If CloudShell restarts and your variables are gone, run `source helpers.sh; source find-ids.sh` to get them back. Lessons 4-6 use this network.

## Common mistakes
- Everything in public subnets: only load balancers and NAT gateways belong there.
- `0.0.0.0/0` on the database port (5432): scanners will find it. The source should be the web tier's security group.
- Overlapping CIDRs: two VPCs with overlapping ranges can never be peered. That's why staging gets `10.1.0.0/16`.
- A single NAT gateway as a hidden single point of failure: if zone A fails, zone B loses its way out. Production: one NAT per AZ.
- Forgetting NAT costs: it bills every hour and every GB. Delete what you don't use; use VPC endpoints (lesson 5) for AWS services.

## Clean up
Keep the network if you go straight on to lessons 4-6 (they build on it). When you are done for the day, first run the clean up of any later lesson you did (4, 5, 6), then:
```bash
bash cleanup.sh
```
It runs, in order: `delete-nat-gateway` + `wait nat-gateway-deleted`, `release-address` (Elastic IP), `delete-security-group` (db, web, alb), `delete-subnet` x6, `delete-route-table` x3, `detach-internet-gateway` + `delete-internet-gateway`, `delete-vpc`. Check nothing is left:
```bash
aws ec2 describe-nat-gateways --filter Name=state,Values=available,pending --query "NatGateways[].NatGatewayId"
aws ec2 describe-addresses --query "Addresses[].AllocationId"
```
Both should print `[]`.

## Next
[M10-L04 · Compute](../m10-l04-compute/)
