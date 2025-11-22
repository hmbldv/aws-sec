# Terraform configuration
terraform {
  # Require Terraform version 1.0 or newer
  required_version = ">= 1.0"

  # Define required providers
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use AWS provider version 5.x
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = "aws-sec"
      ManagedBy   = "Terraform"
      Environment = "management"
      Purpose     = "terraform-state-backend"
    }
  }
}