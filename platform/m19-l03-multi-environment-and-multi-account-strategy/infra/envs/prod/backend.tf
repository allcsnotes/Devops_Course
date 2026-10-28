terraform {
  backend "local" {
    # lab stand-in for this account's own state bucket (on AWS: an S3 bucket in account 333333333333)
    path = "/srv/tfstate/allcs-prod/platform.tfstate"
  }
}
