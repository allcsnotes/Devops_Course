output "url" { value = "http://${aws_lb.web.dns_name}" }
output "db_endpoint" { value = aws_db_instance.main.address }
output "media_bucket" { value = aws_s3_bucket.media.bucket }
output "vpc_id" { value = module.vpc.vpc_id }
