terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration for remote state
  # Configure via backend.hcl or -backend-config flags:
  #   terraform init -backend-config="bucket=terraform-state-<account-id>-<region>"
  backend "s3" {
    # bucket         = "terraform-state-<account-id>-<region>"  # Configure via backend.hcl
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
      Repository  = "https://github.com/hmbldv/aws-sec"
    }
  }
}
