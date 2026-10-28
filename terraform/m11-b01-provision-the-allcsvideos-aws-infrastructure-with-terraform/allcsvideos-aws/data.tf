resource "aws_db_instance" "main" {
  identifier                  = "allcs-${var.env}"
  engine                      = "postgres"
  engine_version              = "17"
  instance_class              = "db.t3.micro"
  allocated_storage           = 20
  storage_type                = "gp3"
  storage_encrypted           = true
  username                    = "allcs"
  manage_master_user_password = true
  db_subnet_group_name        = module.vpc.database_subnet_group_name
  vpc_security_group_ids      = [aws_security_group.db.id]
  publicly_accessible         = false
  backup_retention_period     = 1
  skip_final_snapshot         = true
}

resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "media" {
  bucket        = "allcs-${var.env}-media-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration { status = "Enabled" }
}
