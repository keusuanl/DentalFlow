terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "networking" {
  source      = "../../modules/networking"
  environment = "dev"
}

module "sqs_sns" {
  source        = "../../modules/sqs_sns"
  environment   = "dev"
  s3_bucket_arn = module.s3.bucket_arn
}

module "s3" {
  source           = "../../modules/s3"
  environment      = "dev"
  bucket_name      = "dentalflow-scans-dev-542495333390"
  upload_queue_arn = module.sqs_sns.upload_queue_arn
}

module "ecs" {
  source             = "../../modules/ecs"
  environment        = "dev"
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  container_image    = "542495333390.dkr.ecr.us-east-1.amazonaws.com/dentalflow-dev-app:latest"
  container_port     = 8000
  database_url             = var.database_url
  jwt_secret                = var.jwt_secret
  s3_bucket_name             = module.s3.bucket_id
  upload_queue_url           = module.sqs_sns.upload_queue_url
  notification_topic_arn     = module.sqs_sns.notification_topic_arn
}

module "rds" {
  source                = "../../modules/rds"
  environment            = "dev"
  vpc_id                 = module.networking.vpc_id
  private_subnet_ids     = module.networking.private_subnet_ids
  app_security_group_id  = module.ecs.ecs_tasks_security_group_id
}
