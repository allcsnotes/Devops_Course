# used only for the offline terraform validate run (hashicorp/terraform:1.16.6, init -backend=false)
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "6.69.1" }
  }
}
provider "aws" { region = "us-east-1" }
