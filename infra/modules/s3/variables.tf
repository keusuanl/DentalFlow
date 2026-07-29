variable "environment" {
  description = "Environment name (e.g. dev, staging, prod) - used for resource naming and tagging"
  type        = string
}

variable "bucket_name" {
  description = "Globally unique name for the S3 bucket"
  type        = string
}

variable "upload_queue_arn" {
  description = "ARN of the SQS queue to notify when a scan file is uploaded"
  type        = string
}
