terraform {
  backend "local" {
    # lab stand-in for this account's own state bucket (on AWS: an S3 bucket in account 111111111111)
    path = "/srv/tfstate/allcs-dev/platform.tfstate"
  }
}
