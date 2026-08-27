resource "aws_iam_role" "ecs_task_execution" {
  name = "dentalflow-${var.environment}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "dentalflow-${var.environment}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Security group for the Application Load Balancer - open to the internet on 80
resource "aws_security_group" "alb" {
  name        = "dentalflow-${var.environment}-alb-sg"
  description = "Allow inbound HTTP from the internet to the ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "dentalflow-${var.environment}-alb-sg"
    Environment = var.environment
  }
}

# Security group for ECS tasks - only accepts traffic FROM the ALB, never the internet directly
resource "aws_security_group" "ecs_tasks" {
  name        = "dentalflow-${var.environment}-ecs-tasks-sg"
  description = "Allow inbound traffic only from the ALB security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From ALB only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "dentalflow-${var.environment}-ecs-tasks-sg"
    Environment = var.environment
  }
}

# Target group - the set of ECS tasks the ALB will route traffic to
resource "aws_lb_target_group" "ecs" {
  name_prefix        = "dtg-"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Environment = var.environment
  }
}

# The Application Load Balancer itself - sits in the public subnets
resource "aws_lb" "main" {
  name               = "dentalflow-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    Environment = var.environment
  }
}

# Listener - tells the ALB "when traffic arrives on port 80, send it to this target group"
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }
}

# CloudWatch Log Group - where container logs land
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/dentalflow-${var.environment}"
  retention_in_days = 14

  tags = {
    Environment = var.environment
  }
}

# ECS Cluster - the logical grouping our service runs inside
resource "aws_ecs_cluster" "main" {
  name = "dentalflow-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Environment = var.environment
  }
}

# Task Definition - describes the container: image, ports, resources, roles, logging
resource "aws_ecs_task_definition" "app" {
  family                   = "dentalflow-${var.environment}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "dentalflow-app"
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "DATABASE_URL", value = var.database_url },
        { name = "JWT_SECRET", value = var.jwt_secret },
        { name = "JWT_ALGORITHM", value = "HS256" },
        { name = "ACCESS_TOKEN_EXPIRE_MINUTES", value = "30" },
        { name = "AWS_REGION", value = "us-east-1" },
        { name = "S3_BUCKET_NAME", value = var.s3_bucket_name },
        { name = "UPLOAD_QUEUE_URL", value = var.upload_queue_url },
        { name = "NOTIFICATION_TOPIC_ARN", value = var.notification_topic_arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = {
    Environment = var.environment
  }
}

resource "aws_ecs_service" "app" {
  name            = "dentalflow-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "dentalflow-app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
}

# ECR repository - private registry for our application's container images
resource "aws_ecr_repository" "app" {
  name                 = "dentalflow-${var.environment}-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_ssm" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Scoped S3 access for the application task role, put and get only, only within
# this bucket's scans prefix, matching the object key pattern from ADR-0002.
resource "aws_iam_role_policy" "ecs_task_s3_scans" {
  name = "dentalflow-${var.environment}-ecs-task-s3-scans"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${var.s3_bucket_arn}/scans/*"
      }
    ]
  })
}

# SQS access for the application task role, receive and delete on the upload queue
# only, matching what the background consumer in sqs_consumer.py actually does.
resource "aws_iam_role_policy" "ecs_task_sqs_upload" {
  name = "dentalflow-${var.environment}-ecs-task-sqs-upload"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.upload_queue_arn
      }
    ]
  })
}

# SNS publish for the application task role, matching what sns_service.py does on
# order status transitions.
resource "aws_iam_role_policy" "ecs_task_sns_publish" {
  name = "dentalflow-${var.environment}-ecs-task-sns-publish"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.notification_topic_arn_for_iam
      }
    ]
  })
}
