
variable "database_url" {
  description = "Full database connection string (temporary plain env var)"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT signing secret (temporary plain env var)"
  type        = string
  sensitive   = true
}
