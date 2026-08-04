# Security group - only accepts traffic from the application's (ECS tasks') security group
resource "aws_security_group" "rds" {
  name        = "dentalflow-${var.environment}-rds-sg"
  description = "Allow inbound Postgres traffic only from the application security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from ECS tasks only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "dentalflow-${var.environment}-rds-sg"
    Environment = var.environment
  }
}

# DB subnet group - tells RDS which subnets it's allowed to place instances in
resource "aws_db_subnet_group" "main" {
  name       = "dentalflow-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Environment = var.environment
  }
}

# Generate a random password at apply time - never typed or hardcoded anywhere
resource "random_password" "db_password" {
  length  = 20
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store the generated credentials in Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "dentalflow-${var.environment}-db-credentials"

  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    dbname   = var.db_name
  })
}

resource "aws_db_instance" "main" {
  identifier     = "dentalflow-${var.environment}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = var.multi_az
  publicly_accessible = false

  backup_retention_period = 7
  skip_final_snapshot     = true

  tags = {
    Environment = var.environment
  }
}
