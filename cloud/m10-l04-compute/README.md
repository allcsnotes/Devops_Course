# M10-L04 · Compute
> Video: Module 10, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- An EC2 instance = an **AMI** (the boot disk) + an **instance type** (read `t3.micro` as series, generation, size)
- Why you look up the AMI ID from a public **SSM parameter** instead of hard-coding it
- **User data**: a script cloud-init runs once at first boot, and IMDSv2 (metadata with a session token)
- The fleet: **launch template** (recipe) -> **Auto Scaling group** (manager) -> **target group** (guest list with health checks) -> **Application Load Balancer** (front door)
- Self-healing: terminate an instance and watch the group replace it; EC2 vs ELB health checks
- Session Manager instead of SSH, and the four ways to pay (On-Demand, Savings Plans/Reserved, Spot)

## Before you start
- AWS CloudShell in **us-east-1** with this repo cloned.
- The network from [M10-L03](../m10-l03-vpc-networking/) must exist (VPC, `public-a/b`, `app-a/b`, NAT gateway, security groups `allcs-alb` and `allcs-web`).
  If your CloudShell variables are gone, reload them:
  ```bash
  cd Devops_Course/cloud/m10-l03-vpc-networking && source helpers.sh && source find-ids.sh && cd ../m10-l04-compute
  ```

> **Cost warning** (approx. us-east-1 On-Demand, check the EC2 and ELB pricing pages):
> - each `t3.micro` instance about **US$0.0104/hour** (2-3 of them in this lesson)
> - the Application Load Balancer about **US$0.0225/hour** plus a small LCU charge
> - plus the NAT gateway still running from lesson 3 (~US$0.05/hour with its IP)
>
> Together roughly **US$0.10/hour**. Run the [Clean up](#clean-up) as soon as you finish.
>
> Some sandbox/playground accounts only allow T-series instances in **standard** CPU credit mode (t3 defaults to *unlimited*). If yours does, add `"CreditSpecification":{"CpuCredits":"standard"}` to the launch template data in step 3.

## Files in this folder
| File | What it is |
|---|---|
| `userdata.sh` | first-boot script: installs nginx and writes "allcsvideos web on <instance-id> in <zone>" as the home page |
| `cleanup.sh` | deletes the ASG (and instances), ALB, target group and launch template, in order |

## Follow along
1. Look up the latest Amazon Linux 2023 AMI for this region (free):
   ```bash
   AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text); echo $AMI
   aws ec2 describe-images --image-ids $AMI --query "Images[0].[Name,Architecture,CreationDate]" --output table
   ```
   In the video: `ami-0567589d25e06853e`, `al2023-ami-2023.12.20261016.0-kernel-6.18-x86_64`. You will get a newer one; that is the point.

2. Read the user data script:
   ```bash
   cat userdata.sh
   ```
   It gets an IMDSv2 token with a `PUT`, then the instance ID and zone, and writes them into nginx's home page. Its log ends up in `/var/log/cloud-init-output.log` on the instance. Limit: 16 KB.

3. The launch template `allcs-web`, version `v1` (free): AMI, `t3.micro`, the `allcs-web` security group, IMDSv2 required, user data in base64, a Name tag:
   ```bash
   LT=$(aws ec2 create-launch-template --launch-template-name allcs-web --version-description v1 --launch-template-data "{\"ImageId\":\"$AMI\",\"InstanceType\":\"t3.micro\",\"SecurityGroupIds\":[\"$SGWEB\"],\"MetadataOptions\":{\"HttpTokens\":\"required\"},\"UserData\":\"$(base64 -w0 userdata.sh)\",\"TagSpecifications\":[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"allcs-web\"},{\"Key\":\"Project\",\"Value\":\"allcsvideos\"}]}]}" --query LaunchTemplate.LaunchTemplateId --output text); echo $LT
   ```
   You should see an ID like `lt-06163470f9db5304e`. Templates are immutable: a change means version 2.

4. The target group (free), with a faster health check (every 10 s, healthy after 2 passes):
   ```bash
   TG=$(aws elbv2 create-target-group --name allcs-web-tg --protocol HTTP --port 80 --vpc-id $VPC --health-check-path / --health-check-interval-seconds 10 --healthy-threshold-count 2 --query "TargetGroups[0].TargetGroupArn" --output text); echo $TG
   ```

5. The load balancer in the two public subnets (**starts billing**, ~US$0.0225/h) and its listener:
   ```bash
   ALB=$(aws elbv2 create-load-balancer --name allcs-alb --subnets $PUBA $PUBB --security-groups $SGALB --query "LoadBalancers[0].LoadBalancerArn" --output text); DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB --query "LoadBalancers[0].DNSName" --output text); echo $DNS
   aws elbv2 create-listener --load-balancer-arn $ALB --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TG --query "Listeners[0].[Port,Protocol]" --output text
   ```
   You should see a DNS name like `allcs-alb-396520785.us-east-1.elb.amazonaws.com`, then `80 HTTP`.

6. The Auto Scaling group: min 2, max 4, desired 2, in the two **app** subnets, ELB health checks with a 60 s grace period (**starts 2 x t3.micro**, ~US$0.0104/h each):
   ```bash
   aws autoscaling create-auto-scaling-group --auto-scaling-group-name allcs-web-asg --launch-template LaunchTemplateId=$LT,Version=1 --min-size 2 --max-size 4 --desired-capacity 2 --vpc-zone-identifier "$APPA,$APPB" --target-group-arns $TG --health-check-type ELB --health-check-grace-period 60 && echo ASG created
   sleep 20; aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names allcs-web-asg --query "AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]" --output table
   ```
   You should see two instances, one in `us-east-1a` and one in `us-east-1b`, `InService`, `Healthy`.

7. Wait for the load balancer and for 2 healthy targets:
   ```bash
   time aws elbv2 wait load-balancer-available --load-balancer-arns $ALB
   for i in $(seq 1 30); do H=$(aws elbv2 describe-target-health --target-group-arn $TG --query "length(TargetHealthDescriptions[?TargetHealth.State==\`healthy\`])"); [ "$H" = "2" ] && break; sleep 10; done; echo healthy=$H after $((i*10))s
   aws elbv2 describe-target-health --target-group-arn $TG --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output table
   ```
   In the video the wait took `1m31s`, then `healthy=2 after 10s`.

8. One address, a fleet behind it:
   ```bash
   for i in 1 2 3 4 5 6; do curl -s http://$DNS/; done
   ```
   You should see two different servers answer, for example:
   ```
   allcsvideos web on i-02ff74b59ba4534c6 in us-east-1b
   allcsvideos web on i-05eb4dd3a0961719b in us-east-1a
   ```
   Not strict alternation: each ALB node picks targets itself.

9. The servers are private (no public IP):
   ```bash
   aws ec2 describe-instances --filters Name=tag:Name,Values=allcs-web Name=instance-state-name,Values=running --query "Reservations[].Instances[].[InstanceId,PrivateIpAddress,PublicIpAddress,Placement.AvailabilityZone]" --output table
   ```
   Private IPs like `10.0.2.76` and `10.0.1.30`; the public IP column says `None`.

10. Break it on purpose: raise desired capacity to 3, then terminate one instance by hand:
    ```bash
    aws autoscaling set-desired-capacity --auto-scaling-group-name allcs-web-asg --desired-capacity 3 && echo desired=3
    VICTIM=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names allcs-web-asg --query "AutoScalingGroups[0].Instances[0].InstanceId" --output text); aws ec2 terminate-instances --instance-ids $VICTIM --query "TerminatingInstances[0].[InstanceId,CurrentState.Name]" --output text
    sleep 60; aws autoscaling describe-scaling-activities --auto-scaling-group-name allcs-web-asg --max-items 5 --query "Activities[].[StatusCode,Description]" --output table
    ```
    Read the activities bottom-up (newest first):
    ```
    |  Successful                      |  Launching a new EC2 instance: i-0bbecfa4bd501dd6f   <- the replacement nobody asked for
    |  WaitingForELBConnectionDraining |  Terminating EC2 instance: i-02ff74b59ba4534c6 - Waiting For ELB Connection Draining.
    |  Successful                      |  Launching a new EC2 instance: i-0a221f858f036acf1   <- desired 3
    |  Successful                      |  Launching a new EC2 instance: i-05eb4dd3a0961719b
    |  Successful                      |  Launching a new EC2 instance: i-02ff74b59ba4534c6
    ```

11. Wait for 3 healthy targets and test again:
    ```bash
    for i in $(seq 1 30); do H=$(aws elbv2 describe-target-health --target-group-arn $TG --query "length(TargetHealthDescriptions[?TargetHealth.State==\`healthy\`])"); [ "$H" = "3" ] && break; sleep 10; done; echo healthy=$H; for i in 1 2 3 4 5 6; do curl -s http://$DNS/; done
    ```
    `healthy=3`. In the video only two servers answered the six requests: the replacement was still registering. Run the curl loop again and you will see it too.

## Common mistakes
- Hard-coded AMI IDs: they differ per region and go stale. Look them up at deploy time (SSM parameter or your golden image).
- Pets instead of cattle: a fix made by hand over SSH is lost when the group replaces the instance. Change the template or image.
- A health check path that needs the database: when the DB blips, every target fails together and ELB checks may replace healthy servers.
- A single-AZ group: give the group subnets in at least two zones.
- Public IPs on app instances: keep them in private subnets behind the ALB, trusting only its security group.

## Clean up
Do this as soon as you finish (the ALB and instances bill every hour):
```bash
bash cleanup.sh
```
It runs `aws autoscaling delete-auto-scaling-group --auto-scaling-group-name allcs-web-asg --force-delete`, waits for the instances to terminate, then `aws elbv2 delete-load-balancer` (+ wait), `aws elbv2 delete-target-group`, and `aws ec2 delete-launch-template --launch-template-name allcs-web`.

The network from lesson 3 (and its NAT gateway) is still running. Lessons 5 and 6 use it; if you stop here, run `bash ../m10-l03-vpc-networking/cleanup.sh`.

## Next
[M10-L05 · Storage and Databases](../m10-l05-storage-and-databases/)
