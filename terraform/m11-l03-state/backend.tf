terraform {
  backend "s3" {
    bucket       = "allcs-tfstate-CHANGE-ME" # your state bucket name (step 4 fills it in)
    key          = "hello/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
