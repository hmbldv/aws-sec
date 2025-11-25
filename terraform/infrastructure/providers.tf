terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Using local backend for state management
  # State files will be stored locally in terraform.tfstate
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
