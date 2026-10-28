# M10-L01 · The Cloud Model
> Video: Module 10, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- What "the cloud" means (NIST SP 800-145): on-demand self-service, broad network access, resource pooling, rapid elasticity, measured service
- IaaS, PaaS and SaaS: which layers of the stack you manage and which the provider manages
- Regions, availability zones (AZs) and edge locations, and why you compare **zone IDs**, not zone names
- How to choose a region (latency, data residency, price, service availability) and why you design for at least two AZs
- The shared responsibility model: AWS secures *the* cloud, you secure what you put *in* it

## Before you start
- An AWS account (your own, or a sandbox/playground account).
- **AWS CloudShell** (the terminal icon in the AWS console top bar). The AWS CLI is already installed and signed in there. All of Module 10 uses CloudShell in region **us-east-1**.
- No earlier lesson folder is needed.

**Cost: free.** Every command in this lesson only *reads* information. Nothing is created, so there is nothing to delete.

## Files in this folder
| File | What it is |
|---|---|
| `README.md` | This guide |

## Key ideas

### The three service models
| Layer | On premises | IaaS (EC2) | PaaS (Elastic Beanstalk) | SaaS (GitHub, Gmail) |
|---|---|---|---|---|
| Building, power, network, hardware, virtualisation | You | AWS | AWS | Provider |
| Operating system, runtime (Java, Python) | You | **You** | Provider | Provider |
| Application | You | You | **You** | Provider |
| Data, users, access | You | You | You | **You** |

It is a spectrum: a machine (EC2), then code (Beanstalk), then a container image, then a single function (Lambda). One system can mix them, for example PostgreSQL on EC2 (you patch and back up) or on RDS (AWS does that). Lessons 5 and 6 cover those.

### Regions and zones
- A **region** (us-east-1 = N. Virginia, ap-south-1 = Mumbai) is an isolated location with **at least three AZs**.
- An **AZ** is one or more separate data centres with their own power and networking, all within 100 km of each other, joined by fast encrypted links.
- **Edge locations** (750+ CloudFront points of presence) cache content close to users.
- Regions launched after 20 March 2019 are **opt-in**, so a default account lists only 17 regions even though AWS has more (39 launched regions, 124 AZs, checked 21 October 2026).

### Shared responsibility
AWS: buildings, hardware, network, virtualisation. You: on EC2 the guest OS and patches, software, security groups, users and data; on managed services (RDS, S3) still the data, who can reach it, and the settings. Your **data, identities/access and configuration are always yours**. A public S3 bucket is a customer mistake, not an AWS breach.

### Cost basics
Linux EC2 bills per second (60-second minimum), storage per GB-month, many services per request. Data out to the internet is charged per GB after 100 GB/month free. The real danger is **forgotten resources**: a load balancer or NAT gateway bills every hour, used or not. Lesson 6 sets up a billing alarm.

## Follow along
1. Open CloudShell (us-east-1). List the region names enabled for your account:
   ```bash
   aws ec2 describe-regions --query 'Regions[].RegionName' --output text | tr '\t' '\n' | sort | head -40
   aws ec2 describe-regions --query 'length(Regions)'
   ```
   You should see a list from `ap-northeast-1` to `us-west-2`, and a count (17 in the video's account). Opt-in regions such as `ap-south-2` (Hyderabad) are missing unless your account has enabled them.

2. List the availability zones of us-east-1 with their zone IDs:
   ```bash
   aws ec2 describe-availability-zones --region us-east-1 \
     --query 'AvailabilityZones[].[ZoneName,ZoneId,State]' --output table
   ```
   You should see (your name-to-ID mapping may differ):
   ```
   |  us-east-1a|  use1-az4  |  available  |
   |  us-east-1b|  use1-az6  |  available  |
   |  us-east-1c|  use1-az1  |  available  |
   ...
   ```
   The zone **name** (`us-east-1a`) can map to a different physical zone in another account. The zone **ID** (`use1-az4`) is the same everywhere.

3. Try another region (Mumbai, then Frankfurt):
   ```bash
   aws ec2 describe-availability-zones --region ap-south-1 \
     --query 'AvailabilityZones[].[ZoneName,ZoneId]' --output table
   aws ec2 describe-availability-zones --region eu-central-1 \
     --query 'AvailabilityZones[].[ZoneName,ZoneId]' --output table
   ```
   In a normal account you get the zones. In the video's sandbox account both were refused:
   ```
   An error occurred (UnauthorizedOperation) ... is not authorized to perform:
   ec2:DescribeAvailabilityZones with an explicit deny in a service control policy
   ```
   That is an organisation **guardrail** (a service control policy allowing only us-east-1). An SCP never grants anything; it caps what permissions can allow, and an explicit deny always wins.

## Common mistakes
- Treating the cloud as "someone else's computer": lifting one server unchanged keeps every old problem, plus a bill.
- Single-AZ everything: one server, one database, one zone. Use at least two zones from day one.
- Ignoring region choice: the console's default region may be far from your users or outside the country your data must stay in.
- Assuming AWS secures your configuration: open firewall rules, public buckets and keys in code are customer mistakes.
- Comparing zone names across accounts: compare zone IDs.

## Try it yourself
1. Run step 2 with `--region us-west-2` and note how many AZs it has.
2. For a student base mostly in India with some in Europe, write down which region you'd choose and why, using the four questions (latency, residency, price, service availability).

## Clean up
Nothing to clean up: this lesson created no resources.

## Next
[M10-L02 · IAM](../m10-l02-iam/)
