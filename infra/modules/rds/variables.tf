variable "environment" {
  description = "Environment name (e.g. dev, staging, prod) - used for resource naming and tagging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to deploy RDS into"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the RDS subnet group"
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security group ID of the application (ECS tasks) allowed to connect to the database"
  type        = string
}

variable "db_name" {
  description = "Name of the initial database to create"
  type        = string
  default     = "dentalflow"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "dentalflow_admin"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Whether to enable Multi-AZ deployment (per ADR-005)"
  type        = bool
  default     = true
}
