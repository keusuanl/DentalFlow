output "upload_queue_arn" {
  description = "ARN of the upload event queue"
  value       = aws_sqs_queue.upload_queue.arn
}

output "upload_queue_url" {
  description = "URL of the upload event queue"
  value       = aws_sqs_queue.upload_queue.id
}

output "notification_topic_arn" {
  description = "ARN of the SNS topic for lab and clinic notifications"
  value       = aws_sns_topic.lab_notifications.arn
}
