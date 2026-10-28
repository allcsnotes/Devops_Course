output "subnets" {
  description = "Map of subnet key (tier-az) to its tier, zone and CIDR."
  value       = local.subnets
}

output "cidrs_by_tier" {
  description = "CIDRs grouped by tier, in zone order."
  value       = { for tier in keys(local.tier_offset) : tier => [for az in var.azs : local.subnets["${tier}-${az}"].cidr] }
}

output "names" {
  description = "Subnet names, sorted."
  value       = sort([for r in terraform_data.subnet : r.input.name])
}
