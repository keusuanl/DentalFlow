output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role (for application permissions)"
  value       = aws_iam_role.ecs_task.arn
}

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "ecs_tasks_security_group_id" {
  description = "Security group ID of the ECS tasks, for other resources (like RDS) to allow traffic from"
  value       = aws_security_group.ecs_tasks.id
}
