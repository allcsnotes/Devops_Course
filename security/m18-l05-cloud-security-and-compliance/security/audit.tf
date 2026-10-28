# allcsvideos account baseline: audit logging (first draft)
resource "aws_s3_bucket" "trail" {
  bucket = "allcs-prod-cloudtrail-logs"
}

resource "aws_cloudtrail" "main" {
  name           = "allcs-trail"
  s3_bucket_name = aws_s3_bucket.trail.id
}
