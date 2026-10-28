# Lab stand-in for the lesson 4 network module: same inputs and outputs, but terraform_data
# instead of aws_vpc / aws_subnet, so the pipeline runs with no cloud and no credentials.
variable "name" { type = string }
variable "cidr" { type = string }
variable "zones" { type = list(string) }

resource "terraform_data" "vpc" {
  input = { name = var.name, cidr = var.cidr }
}

resource "terraform_data" "subnet" {
  for_each = toset(var.zones)
  input = {
    vpc  = terraform_data.vpc.id
    name = "${var.name}-public-${each.key}"
    cidr = cidrsubnet(var.cidr, 8, 101 + index(var.zones, each.key))
  }
}

resource "random_id" "bucket" {
  byte_length = 3
}

output "vpc_name" { value = terraform_data.vpc.output.name }
output "subnets" { value = { for z, s in terraform_data.subnet : z => s.output.cidr } }
output "media_bucket" { value = "${var.name}-media-${random_id.bucket.hex}" }
