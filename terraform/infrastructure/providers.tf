terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration for remote state
  # Run terraform init with -backend-config flags or use backend.hcl
  backend "s3" {
    bucket         = "terraform-state-123456789012-us-west-1"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "aws-sec"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Repository  = "https://gitlab.com/username/aws-sec"
    }
  }
}
