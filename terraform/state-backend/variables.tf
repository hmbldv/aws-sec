# AWS Region for resources
variable "aws_region" {
  description = "AWS region for state management resources"
  type        = string
  default     = "us-west-1"
}

# AWS Account ID for bucket naming
variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
  default     = "" # Set via terraform.tfvars
}

# S3 Bucket name for Terraform state
variable "state_bucket_name" {
  description = "Name of S3 bucket for Terraform state"
  type        = string
  default     = "" # Will be computed if empty
}

# DynamoDB table name for state locking
variable "dynamodb_table_name" {
  description = "Name of DynamoDB table for state locking"
  type        = string
  default     = "terraform-state-lock"
}