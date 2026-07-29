# 1. The bucket itself
resource "aws_s3_bucket" "scans" {
  bucket = var.bucket_name

  tags = {
    Name        = "${var.environment}-dentalflow-scans"
    Environment = var.environment
  }
}

# 2. Block all public access - explicitly declared per ADR-002
resource "aws_s3_bucket_public_access_block" "scans" {
  bucket = aws_s3_bucket.scans.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. Encryption at rest - default SSE-S3 per ADR-002
resource "aws_s3_bucket_server_side_encryption_configuration" "scans" {
  bucket = aws_s3_bucket.scans.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 4. Enforce HTTPS-only - deny any request where aws:SecureTransport is false
resource "aws_s3_bucket_policy" "scans" {
  bucket = aws_s3_bucket.scans.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.scans.arn,
          "${aws_s3_bucket.scans.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Notify the upload queue whenever a new scan file is created in the bucket
resource "aws_s3_bucket_notification" "scan_uploads" {
  bucket = aws_s3_bucket.scans.id

  queue {
    queue_arn = var.upload_queue_arn
    events    = ["s3:ObjectCreated:*"]
  }
}
