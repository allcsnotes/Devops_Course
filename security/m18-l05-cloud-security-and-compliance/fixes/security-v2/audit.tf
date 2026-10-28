# allcsvideos account baseline: audit logging
# The bucket lives in the separate log-archive account (module 19 builds it).
variable "log_archive_bucket" {
  type    = string
  default = "allcs-log-archive-cloudtrail"
}

resource "aws_kms_key" "trail" {
  description         = "CloudTrail log files"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.trail_key.json
}

resource "aws_cloudtrail" "main" {
  #checkov:skip=CKV_AWS_252:no SNS per log file; GuardDuty and Security Hub alert
  #checkov:skip=CKV2_AWS_10:findings go to Security Hub, not CloudWatch Logs
  name                          = "allcs-trail"
  s3_bucket_name                = var.log_archive_bucket
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.trail.arn
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::allcs-prod-media-"]
    }
  }
}
