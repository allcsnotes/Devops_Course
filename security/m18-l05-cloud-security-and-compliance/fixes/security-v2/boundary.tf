# The ceiling for every allcsvideos app role: whatever its own policy says,
# it can never go beyond these services.
resource "aws_iam_policy" "boundary" {
  name   = "allcs-app-boundary"
  policy = data.aws_iam_policy_document.boundary.json
}

data "aws_iam_policy_document" "boundary" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::allcs-*/*"]
  }
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:us-east-1:*:secret:allcs/*"]
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
