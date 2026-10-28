# IAM roles for service accounts (IRSA)
resource "aws_iam_openid_connect_provider" "eks" {
  url            = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  oidc_host = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

data "aws_iam_policy_document" "media_reader_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:allcsvideos:media-reader"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "media_reader" {
  name               = "allcs-media-reader"
  assume_role_policy = data.aws_iam_policy_document.media_reader_trust.json
}

resource "aws_s3_bucket" "media" {
  bucket_prefix = "allcs-eks-media-"
  force_destroy = true
}

resource "aws_s3_object" "notes" {
  bucket  = aws_s3_bucket.media.id
  key     = "lessons/l01/notes.txt"
  content = "Lesson 1 notes\n"
}

# The sandbox blocks inline role policies (iam:PutRolePolicy), so we attach an
# AWS managed read-only policy. In production, scope it to this one bucket.
resource "aws_iam_role_policy_attachment" "media_read" {
  role       = aws_iam_role.media_reader.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}
