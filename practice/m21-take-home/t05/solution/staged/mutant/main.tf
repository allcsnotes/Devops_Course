# Root: the prod network plan from Module 4 (prod 10.0.0.0/16), three zones in ap-south-1.
module "prod" {
  source      = "./modules/subnet-plan"
  environment = "production"
  vpc_cidr    = "10.0.0.0/16"
  azs         = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
  tags        = { owner = "asha", cost-center = "platform" }
}

output "prod_private_cidrs" {
  value = module.prod.cidrs_by_tier["private"]
}
