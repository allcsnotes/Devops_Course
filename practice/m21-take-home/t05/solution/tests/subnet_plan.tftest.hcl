# terraform test: runs offline (no providers, plan only).
variables {
  environment = "staging"
  vpc_cidr    = "10.1.0.0/16"
  azs         = ["ap-south-1a", "ap-south-1b"]
  tags        = { owner = "asha", cost-center = "platform" }
}

run "layout_is_deterministic" {
  command = plan
  module { source = "./modules/subnet-plan" }

  assert {
    condition     = output.cidrs_by_tier["public"] == ["10.1.0.0/24", "10.1.1.0/24"]
    error_message = "public subnets should be 10.1.0.0/24 and 10.1.1.0/24"
  }
  assert {
    condition     = output.cidrs_by_tier["private"] == ["10.1.10.0/24", "10.1.11.0/24"]
    error_message = "private subnets should start at offset 10"
  }
  assert {
    condition     = length(output.subnets) == 6
    error_message = "2 zones x 3 tiers should give 6 subnets"
  }
}

run "names_and_tags" {
  command = plan
  module { source = "./modules/subnet-plan" }

  assert {
    condition     = contains(output.names, "allcs-staging-isolated-ap-south-1b")
    error_message = "names follow allcs-<env>-<tier>-<az>"
  }
  assert {
    condition     = terraform_data.subnet["private-ap-south-1a"].input.tags["managed-by"] == "terraform"
    error_message = "every subnet carries managed-by = terraform"
  }
}

run "rejects_unknown_environment" {
  command = plan
  module { source = "./modules/subnet-plan" }
  variables { environment = "production" }
  expect_failures = [var.environment]
}

run "rejects_bad_cidr" {
  command = plan
  module { source = "./modules/subnet-plan" }
  variables { vpc_cidr = "10.1.0.0/20" }
  expect_failures = [var.vpc_cidr]
}

run "prod_needs_two_zones" {
  command = plan
  module { source = "./modules/subnet-plan" }
  variables {
    environment = "prod"
    azs         = ["ap-south-1a"]
  }
  expect_failures = [var.azs]
}

run "requires_owner_tag" {
  command = plan
  module { source = "./modules/subnet-plan" }
  variables { tags = { owner = "asha" } }
  expect_failures = [var.tags]
}
