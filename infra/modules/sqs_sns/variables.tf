variable "environment" {
  description = "Environment name (e.g. dev, staging, prod) - used for resource naming and tagging"
  type        = string
}

variable "max_receive_count" {
  description = "Number of times a message can be received before moving to the DLQ"
  type        = number
  default     = 5
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket allowed to send messages to the upload queue"
  type        = string
}
