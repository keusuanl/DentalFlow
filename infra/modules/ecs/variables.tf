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
