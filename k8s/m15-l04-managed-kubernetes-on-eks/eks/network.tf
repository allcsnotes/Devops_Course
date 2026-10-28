module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name            = var.cluster_name
  cidr            = "10.20.0.0/16"
  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.20.101.0/24", "10.20.102.0/24"]
  private_subnets = ["10.20.1.0/24", "10.20.2.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}
