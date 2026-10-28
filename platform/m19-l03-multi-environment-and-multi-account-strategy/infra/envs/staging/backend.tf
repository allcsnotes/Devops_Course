terraform {
  backend "local" {
    # lab stand-in for this account's own state bucket (on AWS: an S3 bucket in account 222222222222)
    path = "/srv/tfstate/allcs-staging/platform.tfstate"
  }
}
