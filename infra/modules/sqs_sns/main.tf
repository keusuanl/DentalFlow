# Upload queue and its DLQ

resource "aws_sqs_queue" "upload_dlq" {
  name = "${var.environment}-dentalflow-upload-dlq"

  tags = {
    Environment = var.environment
  }
}

resource "aws_sqs_queue" "upload_queue" {
  name = "${var.environment}-dentalflow-upload-queue"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.upload_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Environment = var.environment
  }
}

# Notification queue and its DLQ

resource "aws_sqs_queue" "notification_dlq" {
  name = "${var.environment}-dentalflow-notification-dlq"

  tags = {
    Environment = var.environment
  }
}

resource "aws_sqs_queue" "notification_queue" {
  name = "${var.environment}-dentalflow-notification-queue"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notification_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Environment = var.environment
  }
}

# SNS topic for lab and clinic notifications

resource "aws_sns_topic" "lab_notifications" {
  name = "${var.environment}-dentalflow-lab-notifications"

  tags = {
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "notification_queue_sub" {
  topic_arn = aws_sns_topic.lab_notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notification_queue.arn
}

resource "aws_sqs_queue_policy" "allow_sns_to_notification_queue" {
  queue_url = aws_sqs_queue.notification_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSNSPublish"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.notification_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.lab_notifications.arn
          }
        }
      }
    ]
  })
}

# Policy on the upload queue granting S3 permission to deliver into it
resource "aws_sqs_queue_policy" "allow_s3_to_upload_queue" {
  queue_url = aws_sqs_queue.upload_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowS3Publish"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.upload_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = var.s3_bucket_arn
          }
        }
      }
    ]
  })
}
