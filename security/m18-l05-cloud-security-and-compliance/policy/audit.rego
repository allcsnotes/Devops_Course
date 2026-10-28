# allcsvideos guardrails for audit logging, as code
package main

deny contains msg if {
  some name, i
  trail := input.resource.aws_cloudtrail[name][i]
  contains(trail.s3_bucket_name, "aws_s3_bucket.")
  msg := sprintf("aws_cloudtrail.%s: logs go to a bucket in this account, send them to the log-archive account", [name])
}

# a warning, not a failure: there is no AWS organization yet (module 19)
warn contains msg if {
  some name, i
  trail := input.resource.aws_cloudtrail[name][i]
  not trail.is_organization_trail
  msg := sprintf("aws_cloudtrail.%s: not an organization trail yet", [name])
}
