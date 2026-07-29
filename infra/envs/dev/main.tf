terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

