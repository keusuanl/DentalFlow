output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = module.ecs.alb_dns_name
}
