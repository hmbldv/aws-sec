# =============================================================================
# S3 Buckets - AWS Config and Macie Data Discovery
# =============================================================================

# -----------------------------------------------------------------------------
# AWS Config Bucket
# -----------------------------------------------------------------------------

# Import existing bucket - run: terraform import aws_s3_bucket.config_bucket config-bucket-<account-id>
resource "aws_s3_bucket" "config_bucket" {
  bucket = "config-bucket-${var.aws_account_id}"

  tags = {
    Name        = "AWS Config Bucket"
    Purpose     = "AWS Config configuration snapshots and history"
    Service     = "AWS Config"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for Config data (retain for compliance, then archive)
resource "aws_s3_bucket_lifecycle_configuration" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    id     = "archive-old-config-data"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    # Retain Config data for 7 years (compliance requirement)
    expiration {
      days = 2555 # ~7 years
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Bucket policy for AWS Config service access
resource "aws_s3_bucket_policy" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = var.aws_account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = var.aws_account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket.arn}/AWSLogs/${var.aws_account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = var.aws_account_id
          }
        }
      },
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = "*"
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.config_bucket.arn,
          "${aws_s3_bucket.config_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Macie Data Discovery Bucket
# -----------------------------------------------------------------------------

# Import existing bucket - run: terraform import aws_s3_bucket.macie_bucket squnks-macie-data-discovery
resource "aws_s3_bucket" "macie_bucket" {
  bucket = "squnks-macie-data-discovery"

  tags = {
    Name        = "Macie Data Discovery Bucket"
    Purpose     = "Amazon Macie sensitive data discovery results"
    Service     = "Amazon Macie"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "macie_bucket" {
  bucket = aws_s3_bucket.macie_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "macie_bucket" {
  bucket = aws_s3_bucket.macie_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "macie_bucket" {
  bucket = aws_s3_bucket.macie_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for Macie results
resource "aws_s3_bucket_lifecycle_configuration" "macie_bucket" {
  bucket = aws_s3_bucket.macie_bucket.id

  rule {
    id     = "archive-old-macie-results"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Keep Macie results for 1 year
    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Bucket policy for Macie service access
resource "aws_s3_bucket_policy" "macie_bucket" {
  bucket = aws_s3_bucket.macie_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMacieToGetBucketLocation"
        Effect = "Allow"
        Principal = {
          Service = "macie.amazonaws.com"
        }
        Action   = "s3:GetBucketLocation"
        Resource = aws_s3_bucket.macie_bucket.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      },
      {
        Sid    = "AllowMacieToPutObject"
        Effect = "Allow"
        Principal = {
          Service = "macie.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.macie_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      },
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = "*"
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.macie_bucket.arn,
          "${aws_s3_bucket.macie_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "DenyUnencryptedObjectUploads"
        Effect = "Deny"
        Principal = "*"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.macie_bucket.arn}/*"
        Condition = {
          Null = {
            "s3:x-amz-server-side-encryption" = "true"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "config_bucket_arn" {
  description = "ARN of the AWS Config S3 bucket"
  value       = aws_s3_bucket.config_bucket.arn
}

output "config_bucket_name" {
  description = "Name of the AWS Config S3 bucket"
  value       = aws_s3_bucket.config_bucket.id
}

output "macie_bucket_arn" {
  description = "ARN of the Macie data discovery S3 bucket"
  value       = aws_s3_bucket.macie_bucket.arn
}

output "macie_bucket_name" {
  description = "Name of the Macie data discovery S3 bucket"
  value       = aws_s3_bucket.macie_bucket.id
}
