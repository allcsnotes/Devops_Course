# allcsvideos account baseline: IAM (first draft)
resource "aws_iam_account_password_policy" "main" {
  minimum_password_length = 8
}

resource "aws_iam_role" "catalog" {
  name               = "allcs-catalog-service"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
}

resource "aws_iam_role_policy" "catalog" {
  name   = "catalog-app"
  role   = aws_iam_role.catalog.id
  policy = data.aws_iam_policy_document.catalog.json
}

data "aws_iam_policy_document" "catalog" {
  statement {
    actions   = ["*"]
    resources = ["*"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::allcs-media/*"]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "ecs_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
