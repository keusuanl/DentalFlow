variable "environment" {
  description = "Environment name (e.g. dev, staging, prod) - used for resource naming and tagging"
  type        = string
}

variable "bucket_name" {
  description = "Globally unique name for the S3 bucket"
  type        = string
}
