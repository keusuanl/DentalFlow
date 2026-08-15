output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = module.ecs.alb_dns_name
}

output "s3_bucket_id" {
  description = "Name of the S3 bucket for scan storage"
  value       = module.s3.bucket_id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for scan storage"
  value       = module.s3.bucket_arn
}

output "upload_queue_url" {
  description = "URL of the SQS upload event queue"
  value       = module.sqs_sns.upload_queue_url
}

output "upload_queue_arn" {
  description = "ARN of the SQS upload event queue"
  value       = module.sqs_sns.upload_queue_arn
}

output "notification_topic_arn" {
  description = "ARN of the SNS topic for lab/clinic notifications"
  value       = module.sqs_sns.notification_topic_arn
}

output "db_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.db_endpoint
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials"
  value       = module.rds.db_secret_arn
  sensitive   = true
}


output "ecr_repository_url" {
  description = "URL of the ECR repository for the backend application image"
  value       = module.ecs.ecr_repository_url
}
