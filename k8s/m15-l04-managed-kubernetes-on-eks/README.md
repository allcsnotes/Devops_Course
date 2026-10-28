# M15-L04 · Managed Kubernetes on EKS
> Video: Module 15, Lesson 4. Watch it first, then follow along here.

> **This lesson costs real money.** It creates resources in your AWS account (us-east-1):
> - the **EKS control plane: USD 0.10 per hour** (standard support), charged every hour the cluster exists, even idle
> - **1 x t3.medium EC2 node** (+ its EBS root volume), billed at the normal on-demand rate
> - **1 NAT gateway + 1 Elastic IP**, billed per hour (and per GB of traffic)
> - a **Classic Load Balancer** while the `web` demo Service exists (step 9; it is deleted in step 10)
> - a tiny S3 bucket with one 15-byte object
>
> Do it in one sitting and run the [Clean up](#clean-up) section the same day. If you continue straight to
> M15-B01, keep the cluster and clean up after that build. Set a billing alarm first (Module 10).

## What you'll learn
- What EKS manages for you (a highly available control plane across three zones) and what stays yours (the data plane).
- The four ways to run nodes: managed node groups, self-managed nodes, Fargate, and EKS Auto Mode.
- A complete EKS cluster in Terraform: VPC with subnet tags, cluster role, access entries (API mode), a self-managed
  node joined with nodeadm, Standard CPU credits and IMDSv2 with hop limit 1.
- How a `LoadBalancer` Service creates a real AWS load balancer, and why the AWS Load Balancer Controller is preferred.
- IRSA: how one ServiceAccount gets one IAM role through OIDC and STS, and why pods cannot borrow the node's role.
- Why `terraform destroy` can get stuck on resources Kubernetes created, and how to clean them up.

## Before you start
- An AWS account (or sandbox) you may create EKS, EC2, VPC, IAM and S3 resources in, region **us-east-1**.
- AWS CloudShell (what the video used) or a terminal with: AWS CLI v2, Terraform (video: v1.16.6), kubectl within one
  minor version of 1.37 (video: client 1.36.2), `curl`.
- Terraform basics and modules from Module 11 (`state rm` is from M11-L06); IAM and ASGs from Module 10.

**About the sandbox.** The video ran in a restricted training sandbox, and every error you see in it was real:
`eks:CreateNodegroup` was not allowed (implicit deny), Fargate profiles were blocked by an organisation SCP (explicit
deny), inline role policies (`iam:PutRolePolicy`) and `eks:DeleteAccessEntry` were not allowed, and the IAM roles had
to be named `eksClusterRole` and `AmazonEKSNodeRole`. The files here are the **final version that worked there**: one
self-managed node. In a normal account the common default is a managed node group, and the S3 role would get a
policy scoped to one bucket. If a role with one of those names already exists in your account, change the `name`
in `iam.tf` / `nodes.tf`.

## Files in this folder
| File | What it is |
|---|---|
| `eks/versions.tf` | Terraform + AWS provider (~> 6.0; video: 6.69.1), region us-east-1, default tags `Project=allcsvideos` |
| `eks/variables.tf` | `cluster_name` = `allcs-eks`, `kubernetes_version` = `1.37`, `node_instance_type` = `t3.medium` |
| `eks/network.tf` | VPC module (~> 6.0; video: 6.7.3): 10.20.0.0/16, 2 zones, 2 public + 2 private subnets, 1 NAT gateway, the `kubernetes.io/role/elb` and `internal-elb` subnet tags |
| `eks/iam.tf` | Trust policies and the cluster role with `AmazonEKSClusterPolicy` |
| `eks/eks.tf` | The cluster: authentication mode `API`, creator gets admin, public + private endpoint |
| `eks/nodes.tf` | Self-managed node: AL2023 EKS AMI from SSM, node role + 3 policies, instance profile, `EC2_LINUX` access entry, NodeConfig user data, launch template (Standard credits, IMDSv2, hop limit 1), ASG of 1 |
| `eks/irsa.tf` | OIDC provider, role `allcs-media-reader` (trust: one ServiceAccount + `sts.amazonaws.com`), S3 bucket + `lessons/l01/notes.txt` |
| `eks/outputs.tf` | Cluster name/version, OIDC issuer, bucket, role ARN, the update-kubeconfig command |
| `eks/k8s/namespace.yaml` | Namespace `allcsvideos` + a LimitRange (per-container defaults and caps) |
| `eks/k8s/web.yaml` | 2 x nginx-unprivileged 1.29.8-alpine + a `LoadBalancer` Service (80 -> 8080) |
| `eks/k8s/irsa.yaml.tpl` | ServiceAccount `media-reader` (role annotation), pod `s3-reader` (uses it), pod `no-irsa` (doesn't); aws-cli 2.38.1 |

## Follow along

1. Get the project into CloudShell (upload the `eks` folder, or clone this repo there) and look at it:
   ```bash
   cd eks
   ls; wc -l *.tf | tail -1
   terraform init
   terraform validate
   ```
   ```
   - Installed hashicorp/aws v6.69.1 (signed by HashiCorp)
   Terraform has been successfully initialized!
   Success! The configuration is valid.
   ```

2. Plan and apply (the cluster alone takes about 10 minutes; the NAT gateway about 2.5):
   ```bash
   terraform plan -out=tfplan
   time terraform apply tfplan
   terraform output
   ```
   In the video, the final version added `aws_eks_access_entry.node` in about 9 s and `aws_autoscaling_group.nodes`
   in about 15 s, after the cluster (`Creation complete after 10m4s`) already existed.

3. Connect kubectl and wait for the node:
   ```bash
   aws eks update-kubeconfig --name allcs-eks --region us-east-1
   for i in $(seq 1 40); do R=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready"); [ "$R" -ge 1 ] && break; sleep 10; done; echo "node Ready after about $((i*10))s"; kubectl get nodes -o wide
   kubectl version 2>&1 | grep -E "Client|Server"
   ```
   ```
   node Ready after about 30s
   ip-10-20-2-13.ec2.internal   Ready   <none>   ...   v1.37.0-eks-...   10.20.2.13   <none>   Amazon Linux 2023...   containerd://2.3.5+unknown
   ```
   A private IP and no external IP.

4. Look at the cluster from the AWS side:
   ```bash
   aws eks describe-cluster --name allcs-eks --query "cluster.[name,version,status,platformVersion,accessConfig.authenticationMode,kubernetesNetworkConfig.serviceIpv4Cidr]" --output table
   aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names allcs-eks-nodes --query "AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity,Instances[0].InstanceId,Instances[0].AvailabilityZone,Instances[0].HealthStatus]" --output table
   aws ec2 describe-instances --filters Name=tag:aws:autoscaling:groupName,Values=allcs-eks-nodes Name=instance-state-name,Values=running --query "Reservations[].Instances[].[InstanceId,InstanceType,ImageId,PrivateIpAddress,PublicIpAddress]" --output table
   aws ec2 describe-instance-credit-specifications --instance-ids $(aws ec2 describe-instances --filters Name=tag:aws:autoscaling:groupName,Values=allcs-eks-nodes Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text) --output table
   aws eks list-access-entries --cluster-name allcs-eks --output table
   ```
   You should see `allcs-eks | 1.37 | ACTIVE | ... | API | 172.20.0.0/16`, an ASG of 1/1/1, a `t3.medium` with
   public IP `None`, `CpuCredits standard`, and an access entry for `arn:aws:iam::123456789012:role/AmazonEKSNodeRole`
   (with your own account ID).

5. Who am I to Kubernetes?
   ```bash
   kubectl auth whoami
   ```
   Your IAM ARN through the AWS IAM authenticator, group `system:authenticated` only - admin comes from the access entry.

6. What runs on an EKS node:
   ```bash
   kubectl get pods -A -o wide
   kubectl get ds -n kube-system
   kubectl get node -o jsonpath="{.items[0].status.capacity}{\"\n\"}{.items[0].status.allocatable}{\"\n\"}"
   ```
   `aws-node` (VPC CNI), two `coredns`, `kube-proxy`; pod IPs are real VPC addresses; no control-plane pods.
   ```
   {"cpu":"2",...,"memory":"3927888Ki","pods":"17"}
   {"cpu":"1930m",...,"memory":"3372880Ki","pods":"17"}
   ```
   17 pods = 3 interfaces x (6 addresses - 1) + 2.

7. A namespace with a LimitRange, and a real workload:
   ```bash
   cat k8s/namespace.yaml; kubectl apply -f k8s/namespace.yaml
   kubectl apply -f k8s/web.yaml && time kubectl rollout status deploy/web -n allcsvideos --timeout=300s
   kubectl get pods -n allcsvideos -o wide; kubectl get nodes
   kubectl get svc web -n allcsvideos
   ```
   `EXTERNAL-IP` is a hostname ending in `elb.amazonaws.com` - a real load balancer (on kind it stayed pending).

8. Wait for the load balancer to answer (about 90 s in the video):
   ```bash
   H=$(kubectl get svc web -n allcsvideos -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"); for i in $(seq 1 40); do C=$(curl -s -o /dev/null -w "%{http_code}" http://$H/); [ "$C" = "200" ] && break; sleep 10; done; echo "HTTP $C after $((i*10))s"; curl -s http://$H/ | grep -o "<title>.*</title>"
   ```
   ```
   HTTP 200 after 90s
   <title>Welcome to nginx!</title>
   ```

9. Which load balancer was that?
   ```bash
   aws elb describe-load-balancers --query "LoadBalancerDescriptions[].[Scheme,length(Instances),length(Subnets)]" --output table
   ```
   `internet-facing | 1 | 2`: a Classic Load Balancer in the two public subnets (found through the `elb` tag),
   created by Kubernetes' legacy AWS cloud provider.

10. Delete the Service - and with it the load balancer (do this before any destroy):
    ```bash
    kubectl delete -f k8s/web.yaml; sleep 30; aws elb describe-load-balancers --query "length(LoadBalancerDescriptions)"
    ```
    `0`.

11. IRSA. Fill in the role ARN and bucket name from Terraform, then apply:
    ```bash
    ROLE_ARN=$(terraform output -raw media_reader_role_arn); BUCKET=$(terraform output -raw media_bucket)
    sed -e "s|\${ROLE_ARN}|$ROLE_ARN|" -e "s|\${BUCKET}|$BUCKET|g" k8s/irsa.yaml.tpl > k8s/irsa.yaml
    head -8 k8s/irsa.yaml
    kubectl apply -f k8s/irsa.yaml
    time kubectl wait --for=jsonpath="{.status.phase}"=Succeeded pod/s3-reader pod/no-irsa -n allcsvideos --timeout=300s
    kubectl get pods -n allcsvideos
    ```

12. What the LimitRange and the pod identity webhook added:
    ```bash
    kubectl get pod s3-reader -n allcsvideos -o jsonpath="{.spec.containers[0].resources}{\"\n\"}"
    kubectl get pod s3-reader -n allcsvideos -o jsonpath="{range .spec.containers[0].env[*]}{.name}={.value}{\"\n\"}{end}"
    kubectl get pod s3-reader -n allcsvideos -o jsonpath="{.spec.volumes[?(@.name==\"aws-iam-token\")]}"; echo
    ```
    ```
    {"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}
    AWS_ROLE_ARN=arn:aws:iam::123456789012:role/allcs-media-reader
    AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
    {"name":"aws-iam-token","projected":{...{"serviceAccountToken":{"audience":"sts.amazonaws.com","expirationSeconds":86400,"path":"token"}}]}}
    ```

13. The proof:
    ```bash
    kubectl logs s3-reader -n allcsvideos
    kubectl logs no-irsa -n allcsvideos
    kubectl delete pod s3-reader no-irsa -n allcsvideos
    ```
    ```
    arn:aws:sts::123456789012:assumed-role/allcs-media-reader/botocore-session-...
    2026-10-21 08:33:35         15 lessons/l01/notes.txt
    2026-10-21 08:29:27 do-course-caps-...          <- another bucket: the policy is too broad
    ...
    aws: [ERROR]: An error occurred (NoCredentials): Unable to locate credentials. ...
    ```
    `no-irsa` cannot reach the node's role because the launch template sets hop limit 1. The third line of
    `s3-reader` shows why the policy must be scoped: `AmazonS3ReadOnlyAccess` reads every bucket in the account.

Not run in the video (explained only): managed node groups, Fargate, EKS Auto Mode, the AWS Load Balancer
Controller, EKS Pod Identity, cluster upgrades, EKS add-ons, Cluster Autoscaler and Karpenter.

## Common mistakes
- Forgetting the subnet tags: a `LoadBalancer` Service then cannot find a subnet.
- Nodes in public subnets: only load balancers and NAT gateways belong there.
- Pods borrowing the node's role: without IMDSv2 and a hop limit of 1, any pod can take the node's credentials.
- An IRSA trust policy with the wrong `sub` (another namespace, a typo in the ServiceAccount name): `AssumeRoleWithWebIdentity` is denied.
- Resources created by Kubernetes blocking `terraform destroy`: load balancers, CNI network interfaces, the cluster security group. Delete Services first, then check.
- A role policy that is too broad: IRSA picks the pod; the policy picks the buckets. In production: `s3:ListBucket` on the bucket and `s3:GetObject` on its objects only.
- T3 instances default to unlimited CPU credits: set `credit_specification` to `standard` (done in `nodes.tf`).

## Clean up
Delete everything the same day. Order matters: Services (load balancers) first, then Terraform, then leftovers.

1. Make sure no `LoadBalancer` Service is left, and remove the demo namespace:
   ```bash
   kubectl get svc -A | grep LoadBalancer
   kubectl delete namespace allcsvideos
   aws elb describe-load-balancers --query "length(LoadBalancerDescriptions)"
   ```
2. Destroy:
   ```bash
   time terraform destroy -auto-approve
   ```
3. If destroy fails with `not authorized to perform: eks:DeleteAccessEntry` (the sandbox in the video), Terraform
   only needs to *forget* that entry - deleting the cluster removes its access entries anyway:
   ```bash
   terraform state rm aws_eks_access_entry.node
   time terraform destroy -auto-approve
   ```
4. If destroy hangs on a **private subnet**, look (in a second terminal) for a network interface the VPC CNI left behind,
   and delete it:
   ```bash
   VPC=$(aws ec2 describe-vpcs --filters Name=tag:Project,Values=allcsvideos --query "Vpcs[0].VpcId" --output text)
   aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=$VPC Name=status,Values=available --query "NetworkInterfaces[].[NetworkInterfaceId,Status,Description]" --output table
   aws ec2 delete-network-interface --network-interface-id <eni-id from the table, description aws-K8S-i-...>
   ```
5. If destroy hangs on the **VPC**, the security group EKS created for the cluster (`eks-cluster-sg-allcs-eks-...`) is
   still there. Terraform never created it, so delete it by hand:
   ```bash
   aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC --query "SecurityGroups[?GroupName!=\`default\`].[GroupId,GroupName]" --output table
   aws ec2 delete-security-group --group-id <sg-id of eks-cluster-sg-allcs-eks-...>
   ```
   The waiting destroy then finishes (`Destroy complete!`; about 11 minutes in the video).
6. Final check - every line should print `0` or nothing:
   ```bash
   terraform state list | wc -l
   aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running --query "length(Reservations[].Instances[])"; aws eks list-clusters --output text; aws elb describe-load-balancers --query "length(LoadBalancerDescriptions)"; aws ec2 describe-vpcs --filters Name=tag:Project,Values=allcsvideos --query "length(Vpcs)"
   ```
   Also remove the kubeconfig context if you like: `kubectl config delete-context arn:aws:eks:us-east-1:<account-id>:cluster/allcs-eks`.

## Next
[M15-B01 · Deploy allcsvideos to EKS with Helm and Argo CD](../m15-b01-deploy-allcsvideos-to-eks-with-helm-and-argo-cd/) - this same cluster, a Helm chart, GitOps, and canary releases with Argo Rollouts.
