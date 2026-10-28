# allcsvideos account baseline: IAM
resource "aws_iam_account_password_policy" "main" {
  #checkov:skip=CKV_AWS_9:no forced expiry: NIST SP 800-63B, and CIS since v1.4
  minimum_password_length      = 14
  require_lowercase_characters = true
  require_uppercase_characters = true
  require_numbers              = true
  require_symbols              = true
  password_reuse_prevention    = 24
}

resource "aws_iam_role" "catalog" {
  name                 = "allcs-catalog-service"
  assume_role_policy   = data.aws_iam_policy_document.ecs_trust.json
  permissions_boundary = aws_iam_policy.boundary.arn
}

resource "aws_iam_role_policy" "catalog" {
  name   = "catalog-app"
  role   = aws_iam_role.catalog.id
  policy = data.aws_iam_policy_document.catalog.json
}

data "aws_iam_policy_document" "catalog" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::allcs-prod-media-*/*"]
  }
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:us-east-1:*:secret:allcs/prod/db-*"]
  }
}
