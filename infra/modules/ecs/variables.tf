variable "environment" {
  description = "Environment name (e.g. dev, staging, prod) - used for resource naming and tagging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to deploy ECS resources into"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the Application Load Balancer"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the ECS Fargate tasks"
  type        = list(string)
}

variable "container_image" {
  description = "Docker image to run (placeholder until FastAPI image exists)"
  type        = string
  default     = "public.ecr.aws/nginx/nginx:latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate task memory in MB (512 = 0.5 GB)"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Number of tasks to run (minimum 2 per ADR-004, one per AZ)"
  type        = number
  default     = 2
}

variable "database_url" {
  description = "Full database connection string (temporary plain env var, to be moved to Secrets Manager)"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT signing secret (temporary plain env var, to be moved to Secrets Manager)"
  type        = string
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "S3 bucket name for scan storage"
  type        = string
}

variable "upload_queue_url" {
  description = "SQS upload queue URL"
  type        = string
}

variable "notification_topic_arn" {
  description = "SNS notification topic ARN"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket the ECS task role needs read and write access to, for scan uploads and downloads"
  type        = string
}

variable "upload_queue_arn" {
  description = "ARN of the SQS upload queue, for the ECS task role to receive and delete messages"
  type        = string
}

variable "notification_topic_arn_for_iam" {
  description = "ARN of the SNS notification topic, for the ECS task role to publish to"
  type        = string
}
