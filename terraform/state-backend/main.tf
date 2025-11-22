# Generate bucket name if not provided
locals {
  state_bucket_name = var.state_bucket_name != "" ? var.state_bucket_name : "terraform-state-${var.aws_account_id}-${var.aws_region}"
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = local.state_bucket_name

  # Prevent accidental deletion of this bucket
  lifecycle {
    prevent_destroy = false # Set to true in production
  }

  tags = {
    Name        = "Terraform State Bucket"
    Description = "Stores Terraform state files"
  }
}

# Enable versioning on the S3 bucket
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption with AWS managed KMS key
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # Using AES256 (free) instead of KMS to save costs
    }
  }
}

# Block all public access to the bucket
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Optional: Lifecycle policy to manage old state versions
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "archive-old-versions"
    status = "Enabled"

    # Apply to all objects in the bucket
    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"  # Move to cheaper storage after 30 days
    }

    noncurrent_version_expiration {
      noncurrent_days = 90  # Delete versions older than 90 days
    }
  }
}

# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # On-demand pricing
  hash_key     = "LockID"          # MUST be named "LockID" for Terraform

  attribute {
    name = "LockID"
    type = "S" # String type
  }

  tags = {
    Name        = "Terraform State Lock Table"
    Description = "Prevents concurrent Terraform executions"
  }
}