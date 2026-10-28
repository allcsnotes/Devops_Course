# subnet-plan: a deterministic subnet layout for one VPC (no cloud provider needed).
# Tier offsets in the /16: public 0-9, private 10-19, isolated 20-29, one /24 per zone.
locals {
  tier_offset = { public = 0, private = 10, isolated = 20 }

  subnets = merge([
    for tier, offset in local.tier_offset : {
      for i, az in var.azs : "${tier}-${az}" => {
        tier = tier
        az   = az
        cidr = cidrsubnet(var.vpc_cidr, 8, offset + i)
      }
    }
  ]...)

  tags = merge(var.tags, {
    environment = var.environment
    managed-by  = "terraform"
  })
}

# One record per planned subnet. Changing a subnet's CIDR replaces only that record.
resource "terraform_data" "subnet" {
  for_each = local.subnets

  input            = merge(each.value, { name = "allcs-${var.environment}-${each.key}", tags = local.tags })
  triggers_replace = [each.value.cidr]
}

check "no_overlap_with_lab_range" {
  assert {
    condition     = !contains([for s in local.subnets : s.cidr], "10.0.205.0/24")
    error_message = "a subnet overlaps 10.0.205.0/24, which the local lab uses."
  }
}
