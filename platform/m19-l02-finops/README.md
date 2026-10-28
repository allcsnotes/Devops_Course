# M19-L02 · FinOps
> Video: Module 19, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- What FinOps is (the FinOps Foundation definition), its six principles and the Inform, Optimize, Operate loop
- Where cloud money goes (compute, storage, data transfer, managed services) and why cost per unit (per 1,000 plays) beats a bare total
- How On-Demand, Savings Plans and Spot fit different slices of the load, with real AWS list prices
- How to rightsize from measured p95 usage, and turn Kubernetes usage into dollars with OpenCost
- How to enforce cost tags (a ValidatingAdmissionPolicy in the cluster, `default_tags` + validation in Terraform)
- How to show cost on a Grafana dashboard and switch dev off at night with a CronJob

## Before you start
- Docker Desktop with at least 8 GB of memory for its VM (the lab node is a 10-CPU / 7.75 GiB Docker Desktop VM in the video)
- The versions the video used: kind **v0.33.0**, kubectl **v1.37.1**, Helm **v4.3.1**, Terraform **v1.16.6** (only for step 9), plus `curl`, `jq` and `column`
- `manifests/scripts/rightsize.sh` uses bash associative arrays, so it needs **bash 4 or newer**. macOS ships bash 3.2: install a newer bash (for example `brew install bash`) and run the script with it.
- Optional, for the AWS price steps: AWS CLI v2 and your own AWS account (or a sandbox). The calls in this lesson only read data and create nothing.
- Helpful background: M10-L04 (EC2 pricing models), M11 (Terraform), M14 (autoscaling), M15 (Argo CD), M18-L04 (Kyverno).

## Files in this folder
| File | What it is |
| --- | --- |
| `lab/up.sh`, `lab/down.sh` | Create / delete the one-node kind cluster `finops` and build + load the two lab images |
| `lab/kind-cluster.yaml` | The kind config: one control-plane node, longer leader-election timings |
| `lab/port-forward.sh` | Opens Prometheus (9090), OpenCost API (9003), OpenCost UI (9091) and Grafana (3000) on localhost |
| `app/` | The allcsvideos API lab image: a CPU-heavy `/recommend` endpoint (Python standard library) |
| `traffic/` | The load generator image (`traffic.py`, open-loop requests per second) |
| `manifests/namespaces.yaml` | `allcs-prod`, `allcs-dev` (labelled `project: allcsvideos`) and `loadgen` |
| `manifests/apps-prod.yaml`, `apps-dev.yaml` | api, catalog, storefront, copilot: every pod requests 500m CPU and 384Mi, with cost labels |
| `manifests/apps-prod-rightsized.yaml`, `apps-dev-rightsized.yaml` | The same services with requests from `rightsize.sh` |
| `manifests/loadgen.yaml` | The simulated users: 20 req/s to api, 10 to catalog, 10 to storefront, 2 to copilot, 1 to dev |
| `manifests/metrics-server.yaml` | metrics-server v0.9.0 (for `kubectl top`), with `--kubelet-insecure-tls` for kind |
| `manifests/prometheus.yaml` | Prometheus v3.15.0 scraping cAdvisor, OpenCost and itself |
| `manifests/opencost-values.yaml` | OpenCost Helm values: custom prices built from the t3.medium list price |
| `manifests/scripts/rightsize.sh` | Requests vs p95 CPU / peak memory per Deployment, with a suggestion |
| `manifests/scripts/cost.sh` | OpenCost allocation API -> cost per hour and per 730-hour month |
| `manifests/require-cost-labels.yaml` | ValidatingAdmissionPolicy + binding: pods need `team`, `env`, `cost-center` |
| `manifests/untagged.yaml` | A staged "experiment" Deployment with only an `app` label (gets denied) |
| `manifests/grafana.yaml` | Grafana 13.2.4 with a Prometheus data source and the "allcsvideos cost" dashboard |
| `grafana/make_dash.py` | Generates `manifests/grafana.yaml` (only needed if you change the dashboard) |
| `manifests/dev-schedule.yaml` | `dev-sleep` / `dev-wake` CronJobs and a service account that may only scale Deployments in `allcs-dev` |
| `terraform/tags.tf` | AWS provider `default_tags` (Project, Env, Team, CostCenter, ManagedBy) and a `cost_center` validation rule |

## Follow along

### 1. The bill, on paper (optional AWS CLI checks)
The bill in the video is an illustration: the unit prices are real AWS list prices for us-east-1 (checked 21-22 October 2026), the quantities are invented.

| Line | Quantity x price | Per month |
| --- | --- | --- |
| API fleet | 7 x t3.large x 730 h x $0.0832 | $425.15 |
| Forgotten dev environment | 3 x t3.medium x 730 h x $0.0416 | $91.10 |
| EKS control plane | 730 h x $0.10 | $73.00 |
| NAT gateway | 730 h x $0.045 | $32.85 |
| NAT data processed | 500 GB x $0.045 | $22.50 |
| Idle load balancer | 730 h x $0.0225 | $16.43 |
| Public IPv4 addresses | 4 x 730 h x $0.005 | $14.60 |
| **Total** | | **$675.63** |

Unit economics: with an invented 1.2 million video plays, $675.63 / 1,200 = about **56 cents per 1,000 plays**; with 8,000 active students, about 8.4 cents each.

If you have an AWS account, you can check the real prices yourself (these calls are read-only and create nothing):

```bash
aws ec2 describe-instance-types --instance-types t3.micro t3.small t3.medium t3.large m7g.large c7g.large --query 'InstanceTypes[].[InstanceType,VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB,ProcessorInfo.SupportedArchitectures[0]]' --output table
```

```bash
aws pricing get-products --region us-east-1 --service-code AmazonEC2 --filters Type=TERM_MATCH,Field=instanceType,Value=t3.medium Type=TERM_MATCH,Field=location,Value='US East (N. Virginia)' Type=TERM_MATCH,Field=operatingSystem,Value=Linux Type=TERM_MATCH,Field=tenancy,Value=Shared Type=TERM_MATCH,Field=preInstalledSw,Value=NA Type=TERM_MATCH,Field=capacitystatus,Value=Used --query 'PriceList[0]' --output text | jq -r '[.product.attributes.instanceType, (.terms.OnDemand[].priceDimensions[] | .pricePerUnit.USD, .unit, .description)] | @tsv'
```
Repeat with `Value=t3.large` and `Value=m7g.large`. You should see (21 October 2026):
```
t3.medium	0.0416000000	Hrs	$0.0416 per On Demand Linux t3.medium Instance Hour
t3.large	0.0832000000	Hrs	$0.0832 per On Demand Linux t3.large Instance Hour
m7g.large	0.0816000000	Hrs	$0.0816 per On Demand Linux m7g.large Instance Hour
```
All three have 2 vCPUs (t3.medium 4096 MiB, t3.large and m7g.large 8192 MiB; m7g is arm64).

The video also tried `aws ec2 describe-spot-price-history ...`. The training account denied it (explicit deny in a service control policy), so the video shows no spot price. In your own account it may work.

The sizing maths from the video: 7 x t3.medium = $212.58 a month (but t3 is burstable, baseline 20% per vCPU = 0.4 CPU, and the plan needs 0.65 at peak). 4 x m7g.large (2 API copies each) = $238.27 a month with no CPU-credit cliff. Rightsize first, then commit.

### 2. Start the lab cluster
```bash
./lab/up.sh
```
You should see:
```
NAME                   STATUS   ROLES           AGE     VERSION
finops-control-plane   Ready    control-plane   2m30s   v1.37.0
```
Check what the node offers (in the video: 10 CPUs and 8126480Ki = 7.75 GiB, arm64; yours depends on your Docker Desktop settings):
```bash
kubectl describe node finops-control-plane | grep -A6 '^Capacity'
```

### 3. Deploy allcsvideos, metrics, Prometheus and the users
```bash
kubectl apply -f manifests/namespaces.yaml -f manifests/apps-prod.yaml -f manifests/apps-dev.yaml
kubectl apply -f manifests/metrics-server.yaml -f manifests/prometheus.yaml | grep -v rbac
kubectl apply -f manifests/loadgen.yaml
```
Every Deployment uses the same copied template (500m CPU, 384Mi memory) and every pod carries the labels `project`, `env`, `team` and `cost-center`.

### 4. Install OpenCost (chart 2.5.33 = OpenCost 1.121.3)
```bash
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm install opencost opencost/opencost --version 2.5.33 -n opencost --create-namespace -f manifests/opencost-values.yaml
kubectl -n opencost rollout status deploy/opencost --timeout=300s
```
You should see `STATUS: deployed` and `deployment "opencost" successfully rolled out`.

kind has no cloud bill, so `opencost-values.yaml` gives OpenCost custom prices from one real number: the t3.medium price of $0.0416/hour for 2 vCPU + 4 GiB, split half and half (our assumption): **$0.0104 per vCPU-hour** and **$0.0052 per GiB-hour**.

Now let the load run for about **30 minutes** before measuring.

### 5. Measure: kubectl top, then p95 over time
In a second terminal, open the port-forwards and leave them running:
```bash
./lab/port-forward.sh
```
Back in the first terminal:
```bash
kubectl top pods -n allcs-prod
kubectl get deploy -n allcs-prod -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,CPU-REQ:.spec.template.spec.containers[0].resources.requests.cpu,MEM-REQ:.spec.template.spec.containers[0].resources.requests.memory
```
You should see API pods at roughly 76-92m CPU, catalog about 10m, storefront 1-2m, memory 8-12Mi, against requests of 500m / 384Mi each. `top` is one moment; to size, use a percentile over time:
```bash
./manifests/scripts/rightsize.sh allcs-prod 30m
./manifests/scripts/rightsize.sh allcs-dev 30m
```
You should see something like (the video's real result):
```
DEPLOYMENT    CPU-REQ   CPU-P95   USED    MEM-REQ   MEM-PEAK   USED   SUGGEST
api              500m      303m    61%      384Mi       13Mi     3%   cpu=400m memory=64Mi
catalog          500m       43m     9%      384Mi       12Mi     3%   cpu=60m memory=64Mi
copilot          500m       97m    19%      384Mi       12Mi     3%   cpu=130m memory=64Mi
storefront       500m        6m     1%      384Mi        9Mi     2%   cpu=10m memory=64Mi
```
The rule is written in the script: CPU = p95 x 1.3, memory = peak x 1.5, never below 64Mi. In dev, the busiest service uses 11% of its CPU request.

### 6. Turn usage into dollars with OpenCost
Confirm the node price:
```bash
kubectl get node -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory,ARCH:.status.nodeInfo.architecture
curl -s localhost:9090/api/v1/query --data-urlencode 'query={__name__=~"node_(cpu|ram|total)_hourly_cost"}' | jq -r '.data.result[] | "\(.metric.__name__)  \(.value[1])"'
```
You should see `node_cpu_hourly_cost 0.0104`, `node_ram_hourly_cost 0.0052`, and a total of about 0.1443 for a 10-CPU / 7.75 GiB node (x 730 = $105.34 a month). Your total depends on your node size.

Cost per namespace and per team (each pod is charged for the larger of what it requests and what it uses):
```bash
./manifests/scripts/cost.sh namespace 30m
./manifests/scripts/cost.sh label:team 30m
```
You should see something like:
```
NAME                CPU-REQ  CPU-USED  MEM-REQ  MEM-USED  $/HOUR  $/MONTH  EFFICIENCY
allcs-prod          4        0.61      3Gi      0.09Gi    0.0572  41.75    12%
allcs-dev           2        0.04      1.5Gi    0.04Gi    0.0286  20.88    2%
...
NAME             CPU-REQ  CPU-USED  MEM-REQ  MEM-USED  $/HOUR  $/MONTH  EFFICIENCY
courses          3.5      0.59      2.63Gi   0.08Gi    0.05    36.53    13%
__unallocated__  1.35     0.43      1.16Gi   0.88Gi    0.0224  16.33    48%
web              1.5      0.01      1.13Gi   0.03Gi    0.0215  15.66    1%
ai               1        0.06      0.75Gi   0.02Gi    0.0143  10.44    5%
```
`__unallocated__` is everything with no `team` label: kube-system, monitoring, the load generator.

The OpenCost UI shows the same data at http://localhost:9091 (cost by namespace per day, a breakdown table and an idle line; cloud costs stay empty because no cloud bill is connected).

### 7. Optimize: apply the rightsized requests
In a real team this is a pull request, reviewed and synced by Argo CD. Here you apply the files yourself:
```bash
kubectl apply -f manifests/apps-prod-rightsized.yaml -f manifests/apps-dev-rightsized.yaml | grep deployment
kubectl -n allcs-prod rollout status deploy/api --timeout=180s
kubectl get deploy -n allcs-prod -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,CPU-REQ:.spec.template.spec.containers[0].resources.requests.cpu,MEM-REQ:.spec.template.spec.containers[0].resources.requests.memory
```
You should see api 400m, catalog 60m, copilot 130m, storefront 10m, all 64Mi (limit 128Mi).

New requests mean new pods, so this is a rollout. The load generator counted a few failures during it (in the video: 28 failed of 5,203 requests). You can look at its per-second log:
```bash
kubectl -n loadgen exec deploy/users -- tail -5 /tmp/api.log
```
Wait about 20 minutes, then measure again:
```bash
./manifests/scripts/cost.sh namespace 20m
./manifests/scripts/cost.sh label:team 20m
```
In the video: allcs-prod went from $41.75 to $13.07 a month (efficiency 12% -> 32%), allcs-dev from $20.88 to $1.78, team courses from $36.53 to $12.36, web from $15.66 to $0.95. The node itself still costs the same; freed requests become idle cost until fewer nodes run (the M14 node autoscaler).

### 8. Enforce cost labels in the cluster
```bash
kubectl apply -f manifests/require-cost-labels.yaml
kubectl apply -f manifests/untagged.yaml
kubectl get deploy -n allcs-dev
```
You should see the experiment denied at the API server:
```
The deployments "experiment" is invalid: : ValidatingAdmissionPolicy 'require-cost-labels' with binding 'require-cost-labels' denied request: pods need the labels team, env and cost-center (cost allocation); got: app
```

### 9. Enforce cost tags in Terraform
```bash
cd terraform
terraform version
terraform init
terraform validate
terraform plan -var cost_center=marketing
cd ..
```
`validate` says `Success! The configuration is valid.` and the plan fails before anything is created:
```
Error: Invalid value for variable
...
cost_center must look like cc-1234 (ask finance for yours).
```
On AWS, tags only reach the bill after you activate them as **cost allocation tags** in the Billing console (keys can take up to 24 hours to appear and up to 24 more to activate). The video's training account denied Cost Explorer, the cost allocation tag list, the tagging API and Budgets (explicit deny in a service control policy), for example:
```
aws: [ERROR]: An error occurred (AccessDeniedException) when calling the GetCostAndUsage operation: User: arn:aws:iam::123456789012:user/... is not authorized to perform: ce:GetCostAndUsage ... with an explicit deny in a service control policy: ...
```
In companies, billing data usually lives in a separate management account (next lesson).

### 10. Inform: the Grafana cost dashboard
```bash
kubectl apply -f manifests/grafana.yaml
kubectl -n monitoring rollout status deploy/grafana --timeout=180s
```
If `port-forward.sh` was started before Grafana existed, stop it (Ctrl+C) and start it again. Open http://localhost:3000, folder **FinOps**, dashboard **allcsvideos cost**. The cost panels multiply `container_cpu_allocation` by `node_cpu_hourly_cost`, plus memory the same way, summed by namespace or team. The top row shows the node cost per hour and per month, what allcsvideos claims, and the idle share (87.6% in the video after rightsizing).

### 11. Operate: switch dev off at night
```bash
kubectl apply -f manifests/dev-schedule.yaml | grep -v rbac
kubectl -n allcs-dev get cronjobs
kubectl -n allcs-dev create job --from=cronjob/dev-sleep dev-sleep-now
kubectl -n allcs-dev wait --for=condition=complete job/dev-sleep-now --timeout=180s
kubectl -n allcs-dev logs job/dev-sleep-now
kubectl -n allcs-dev get deploy
```
You should see:
```
dev-sleep   0 20 * * 1-5   Asia/Kolkata   False     0        <none>          0s
dev-wake    0 8 * * 1-5    Asia/Kolkata   False     0        <none>          0s
...
deployment.apps/api scaled
deployment.apps/catalog scaled
deployment.apps/copilot scaled
deployment.apps/storefront scaled
```
and every dev Deployment at `0/0`. A few minutes later:
```bash
./manifests/scripts/cost.sh namespace 8m
```
shows `allcs-dev` at 0. Change `timeZone` in `dev-schedule.yaml` to your own time zone if you keep it.

Back on paper: dev on 12 hours on weekdays is 60 of 168 hours, so the forgotten $91.10 becomes $32.54. With the rightsized fleet and the idle load balancer deleted, the illustrated bill falls from $675.63 to $388.06, and cost per 1,000 plays from 56 cents to 32.

## Common mistakes
- **Optimizing before tagging.** Without owners every saving is a negotiation and the unallocated line keeps growing. Tag first.
- **Buying commitments before rightsizing.** A three-year Savings Plan on oversized machines is waste with a contract.
- **Ignoring data transfer.** NAT gateways and cross-zone traffic hide in small per-GB prices.
- **Spot for stateful work.** Spot gives a two-minute warning; use it only for copies you can lose (stateless API extras), never the database.
- **Treating rightsizing as a config tweak.** New requests mean a rollout; old pods stopped before Services stopped sending them traffic. A short `preStop` pause is the usual fix.
- **Sizing from `kubectl top`.** It is one moment; use a percentile over a window.
- **Expecting savings from smaller requests alone.** The node still costs the same until fewer nodes run.
- Running `rightsize.sh` with macOS's bash 3.2 (`declare -A` fails). Use bash 4+.

## Clean up
Stop `port-forward.sh` with Ctrl+C, then:
```bash
./lab/down.sh
helm repo remove opencost
rm -rf terraform/.terraform
```
The AWS commands in this lesson created nothing. Note that AWS charges per Cost Explorer API request, so don't loop those calls.

## Next
[M19-L03 · Multi-Environment and Multi-Account Strategy](../m19-l03-multi-environment-and-multi-account-strategy/)
