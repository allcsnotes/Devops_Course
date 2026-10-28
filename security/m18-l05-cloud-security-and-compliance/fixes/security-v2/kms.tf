# Key policy for the trail key: the account administers it,
# and CloudTrail may only encrypt log files for our trail.
data "aws_caller_identity" "me" {}

data "aws_iam_policy_document" "trail_key" {
  # in a key policy, Resource "*" means this key only (AWS KMS docs)
  #checkov:skip=CKV_AWS_109:key policy, scoped to this key
  #checkov:skip=CKV_AWS_111:key policy, scoped to this key
  #checkov:skip=CKV_AWS_356:key policy, scoped to this key
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.me.account_id}:root"]
    }
  }
  statement {
    sid       = "CloudTrailEncrypt"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${data.aws_caller_identity.me.account_id}:trail/allcs-trail"]
    }
  }
}
