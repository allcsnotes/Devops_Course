#!/usr/bin/env python3
"""Check the allcsvideos network plan: every subnet inside the VPC, no overlaps, no clash with other networks."""
import ipaddress as ip

VPC = ip.ip_network("10.0.0.0/16")
SUBNETS = {
    "public-a": "10.0.101.0/24", "public-b": "10.0.102.0/24",
    "app-a":    "10.0.1.0/24",   "app-b":    "10.0.2.0/24",
    "data-a":   "10.0.21.0/24",  "data-b":   "10.0.22.0/24",
}
OTHERS = {"office VPN": "192.168.10.0/24", "docker default bridge": "172.17.0.0/16",
          "staging VPC (copied)": "10.0.0.0/16", "staging VPC (fixed)": "10.1.0.0/16"}

nets = {name: ip.ip_network(c) for name, c in SUBNETS.items()}
for name, n in nets.items():
    usable = n.num_addresses - 5          # AWS reserves 5 addresses in every subnet
    print(f"{name:9} {str(n):14} inside VPC: {n.subnet_of(VPC)}  usable on AWS: {usable}")
names = list(nets)
for i, a in enumerate(names):
    for b in names[i + 1:]:
        if nets[a].overlaps(nets[b]):
            print(f"OVERLAP: {a} and {b}")
for name, c in OTHERS.items():
    print(f"{name:22} {c:16} overlaps VPC: {ip.ip_network(c).overlaps(VPC)}")
