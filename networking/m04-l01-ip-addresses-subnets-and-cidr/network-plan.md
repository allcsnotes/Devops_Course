# allcsvideos network plan (M04-L01, reused in M10 and M11)

VPC: `10.0.0.0/16` - 65,536 addresses (10.0.0.0 - 10.0.255.255), RFC 1918 private space.
Two availability zones, called zone A and zone B here. Every subnet is a `/24`: 256 addresses, 251 usable on AWS
(AWS reserves 5 per subnet: network address, .1 VPC router, .2 DNS, .3 future use, and the last address).

| Subnet   | Tier    | Zone | CIDR            | Range                       | Addresses | Usable on AWS | What runs here                        |
|----------|---------|------|-----------------|-----------------------------|-----------|---------------|---------------------------------------|
| public-a | public  | A    | `10.0.101.0/24` | 10.0.101.0 - 10.0.101.255   | 256       | 251           | load balancer, NAT gateway, bastion   |
| public-b | public  | B    | `10.0.102.0/24` | 10.0.102.0 - 10.0.102.255   | 256       | 251           | load balancer, NAT gateway            |
| app-a    | private | A    | `10.0.1.0/24`   | 10.0.1.0 - 10.0.1.255       | 256       | 251           | web, API, Course Copilot, Redis       |
| app-b    | private | B    | `10.0.2.0/24`   | 10.0.2.0 - 10.0.2.255       | 256       | 251           | web, API, Course Copilot, Redis       |
| data-a   | private | A    | `10.0.21.0/24`  | 10.0.21.0 - 10.0.21.255     | 256       | 251           | PostgreSQL (primary)                  |
| data-b   | private | B    | `10.0.22.0/24`  | 10.0.22.0 - 10.0.22.255     | 256       | 251           | PostgreSQL (standby)                  |

- Numbering: app subnets 10.0.1-9.x, data 10.0.21-29.x, public 10.0.101-109.x, so a third zone is just `.3`, `.23`, `.103`.
- Everything else in 10.0.0.0/16 (250 more /24s) is free for growth, for example a Kubernetes node range later.
- Do not overlap: office VPN 192.168.10.0/24, Docker default bridge 172.17.0.0/16, staging VPC 10.1.0.0/16
  (a staging VPC copied as 10.0.0.0/16 could never be peered or routed to this one).
- Checked with `ipcalc` and `check_plan.py`.
