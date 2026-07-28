output "bucket_id" {
  description = "ID (name) of the S3 bucket"
  value       = aws_s3_bucket.scans.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.scans.arn
}
