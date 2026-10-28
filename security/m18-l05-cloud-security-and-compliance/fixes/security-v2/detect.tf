# Detection: findings instead of hoping someone reads the logs.
resource "aws_guardduty_detector" "main" {
  #checkov:skip=CKV2_AWS_3:organization-wide setup comes with module 19
  enable = true
}

resource "aws_accessanalyzer_analyzer" "external" {
  analyzer_name = "allcs-external-access"
  type          = "ACCOUNT"
}

resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:us-east-1::standards/cis-aws-foundations-benchmark/v/5.0.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_config_configuration_recorder" "main" {
  name     = "allcs"
  role_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "allcs"
  s3_bucket_name = var.log_archive_bucket
  depends_on     = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "managed" {
  for_each = toset(["ROOT_ACCOUNT_MFA_ENABLED", "IAM_PASSWORD_POLICY", "MULTI_REGION_CLOUD_TRAIL_ENABLED", "ACCESS_KEYS_ROTATED"])
  name     = lower(replace(each.key, "_", "-"))
  source {
    owner             = "AWS"
    source_identifier = each.key
  }
  depends_on = [aws_config_configuration_recorder.main]
}
