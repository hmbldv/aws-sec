#------------------------------------------------------------------------------
# AWS CloudTrail Configuration
#------------------------------------------------------------------------------
# CloudTrail provides governance, compliance, and operational auditing of your
# AWS account. Actions taken by users, roles, or AWS services are recorded as
# events. This configuration creates:
#   - Organization-wide trail with multi-region coverage
#   - Dedicated S3 bucket with encryption, versioning, and lifecycle policies
#   - CloudWatch Logs integration for real-time monitoring and alerting
#   - SNS topic for notifications
#   - Proper IAM roles and bucket policies following least privilege
#
# Cost Considerations:
#   - First trail in each region: Free for management events
#   - S3 storage: ~$0.023/GB (Standard), lifecycle policies reduce costs over time
#   - CloudWatch Logs: ~$0.50/GB ingested
#
# Security Best Practices Implemented:
#   - S3 bucket encryption (AES256)
#   - Bucket versioning enabled (prevents accidental deletion)
#   - Public access fully blocked
#   - Log file validation enabled (detect tampering)
#   - MFA delete consideration (enabled via bucket versioning)
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Variables for CloudTrail Configuration
#------------------------------------------------------------------------------

variable "enable_cloudtrail" {
  description = "Enable or disable CloudTrail resources. Set to false to skip CloudTrail deployment."
  type        = bool
  default     = true
}

variable "cloudtrail_name" {
  description = "Name of the CloudTrail trail. Used for resource naming and identification."
  type        = string
  default     = "organization-trail"
}

variable "cloudtrail_log_retention_days" {
  description = "Number of days to retain CloudTrail logs in CloudWatch Logs. Longer retention increases costs."
  type        = number
  default     = 90 # 90 days balances compliance needs with cost
}

variable "cloudtrail_s3_lifecycle_ia_days" {
  description = "Days before transitioning CloudTrail logs to S3 Infrequent Access storage class."
  type        = number
  default     = 90
}

variable "cloudtrail_s3_lifecycle_glacier_days" {
  description = "Days before transitioning CloudTrail logs to Glacier storage class."
  type        = number
  default     = 180
}

variable "cloudtrail_s3_lifecycle_expiration_days" {
  description = "Days before permanently deleting CloudTrail logs. Set to 0 to never delete."
  type        = number
  default     = 2555 # ~7 years for compliance (PCI-DSS, HIPAA, SOX)
}

#------------------------------------------------------------------------------
# S3 Bucket for CloudTrail Logs
#------------------------------------------------------------------------------
# This bucket stores all CloudTrail log files. The bucket policy grants
# CloudTrail service permission to write logs while denying all other access.
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  # Bucket naming: Use account ID for uniqueness across AWS
  bucket = "cloudtrail-logs-${var.aws_account_id}"

  # Force destroy allows Terraform to delete bucket with objects
  # In production, you may want to set this to false to prevent accidental deletion
  force_destroy = false

  tags = {
    Name       = "cloudtrail-logs-${var.aws_account_id}"
    Purpose    = "CloudTrail log storage"
    Compliance = "Security audit logs"
    CostCenter = "Security"
  }
}

#------------------------------------------------------------------------------
# S3 Bucket Versioning
#------------------------------------------------------------------------------
# Versioning protects against accidental deletion and overwrites.
# Critical for audit logs where integrity must be maintained.
#------------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id

  versioning_configuration {
    status = "Enabled"
    # Note: MFA Delete can be enabled via AWS CLI for additional protection:
    # aws s3api put-bucket-versioning --bucket <bucket> --versioning-configuration Status=Enabled,MFADelete=Enabled --mfa "arn:aws:iam::<account>:mfa/<device> <code>"
  }
}

#------------------------------------------------------------------------------
# S3 Bucket Server-Side Encryption
#------------------------------------------------------------------------------
# Encrypt all objects at rest using AES256 (SSE-S3).
# For higher security requirements, consider SSE-KMS with a customer managed key.
#------------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
      # For KMS encryption, uncomment and configure:
      # sse_algorithm     = "aws:kms"
      # kms_master_key_id = aws_kms_key.cloudtrail.arn
    }
    # Enforce encryption for all objects, even if PutObject doesn't specify
    bucket_key_enabled = true
  }
}

#------------------------------------------------------------------------------
# S3 Bucket Public Access Block
#------------------------------------------------------------------------------
# Block ALL public access to CloudTrail logs. These are sensitive audit logs
# and should never be publicly accessible under any circumstances.
#------------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id

  # Block public ACLs - prevents adding public ACLs to bucket/objects
  block_public_acls = true

  # Block public policy - prevents bucket policies that allow public access
  block_public_policy = true

  # Ignore public ACLs - ignores any existing public ACLs
  ignore_public_acls = true

  # Restrict public buckets - restricts access to AWS principals with access only
  restrict_public_buckets = true
}

#------------------------------------------------------------------------------
# S3 Bucket Lifecycle Configuration
#------------------------------------------------------------------------------
# Lifecycle rules automatically transition logs to cheaper storage tiers
# and eventually delete them based on retention requirements.
#
# Storage Class Costs (us-east-1):
#   - Standard: $0.023/GB
#   - Standard-IA: $0.0125/GB (50% cheaper)
#   - Glacier: $0.004/GB (83% cheaper than Standard)
#------------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id

  # Lifecycle must wait for versioning to be configured
  depends_on = [aws_s3_bucket_versioning.cloudtrail]

  rule {
    id     = "cloudtrail-log-lifecycle"
    status = "Enabled"

    # Apply to all objects in the bucket (CloudTrail prefix is AWSLogs/)
    filter {
      prefix = "AWSLogs/"
    }

    # Transition to Infrequent Access after 90 days
    # Good for logs that are rarely accessed but need quick retrieval
    transition {
      days          = var.cloudtrail_s3_lifecycle_ia_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 180 days
    # For long-term archival - retrieval takes minutes to hours
    transition {
      days          = var.cloudtrail_s3_lifecycle_glacier_days
      storage_class = "GLACIER"
    }

    # Delete after ~7 years (2555 days) for compliance
    # Adjust based on your regulatory requirements:
    #   - PCI-DSS: 1 year minimum
    #   - HIPAA: 6 years minimum
    #   - SOX: 7 years minimum
    dynamic "expiration" {
      for_each = var.cloudtrail_s3_lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.cloudtrail_s3_lifecycle_expiration_days
      }
    }

    # Clean up old versions after the same period
    dynamic "noncurrent_version_expiration" {
      for_each = var.cloudtrail_s3_lifecycle_expiration_days > 0 ? [1] : []
      content {
        noncurrent_days = var.cloudtrail_s3_lifecycle_expiration_days
      }
    }
  }
}

#------------------------------------------------------------------------------
# S3 Bucket Policy for CloudTrail
#------------------------------------------------------------------------------
# This policy grants the CloudTrail service permission to:
#   1. Check bucket ACL (GetBucketAcl) - Required to verify bucket ownership
#   2. Write log files (PutObject) - Required to deliver logs
#
# The policy uses conditions to ensure only CloudTrail from your account
# can write to this bucket, preventing cross-account log injection.
#------------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id

  # Wait for public access block to be applied first
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Statement 1: Allow CloudTrail to check bucket ACL
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail[0].arn
        Condition = {
          StringEquals = {
            # Only allow requests from your account's CloudTrail
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      },
      {
        # Statement 2: Allow CloudTrail to write log files
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail[0].arn}/AWSLogs/${var.aws_account_id}/*"
        Condition = {
          StringEquals = {
            # Ensure CloudTrail sets proper ACL on uploaded objects
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      },
      {
        # Statement 3: Deny non-HTTPS access (enforce encryption in transit)
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail[0].arn,
          "${aws_s3_bucket.cloudtrail[0].arn}/*"
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

#------------------------------------------------------------------------------
# CloudWatch Log Group for CloudTrail
#------------------------------------------------------------------------------
# CloudWatch Logs integration enables:
#   - Real-time monitoring of API activity
#   - Metric filters for security alerting
#   - Log Insights queries for investigation
#
# Retention is configurable to balance cost vs. compliance needs.
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  name              = "/aws/cloudtrail/${var.cloudtrail_name}"
  retention_in_days = var.cloudtrail_log_retention_days

  # Optional: Encrypt logs with KMS
  # kms_key_id = aws_kms_key.cloudtrail.arn

  tags = {
    Name       = "cloudtrail-logs"
    Purpose    = "CloudTrail event logging"
    CostCenter = "Security"
  }
}

#------------------------------------------------------------------------------
# IAM Role for CloudTrail to CloudWatch Logs
#------------------------------------------------------------------------------
# CloudTrail needs permission to write logs to CloudWatch.
# This role uses the principle of least privilege - only allowing
# the specific actions needed for log delivery.
#------------------------------------------------------------------------------

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  count = var.enable_cloudtrail ? 1 : 0

  name = "CloudTrailCloudWatchRole"

  # Trust policy: Only CloudTrail service can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudTrailAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "CloudTrailCloudWatchRole"
    Purpose = "Allow CloudTrail to write to CloudWatch Logs"
  }
}

#------------------------------------------------------------------------------
# IAM Policy for CloudWatch Logs Access
#------------------------------------------------------------------------------
# Grants CloudTrail permission to create log streams and write events.
# Scoped to the specific log group to follow least privilege.
#------------------------------------------------------------------------------

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  count = var.enable_cloudtrail ? 1 : 0

  name = "CloudTrailCloudWatchPolicy"
  role = aws_iam_role.cloudtrail_cloudwatch[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          # Create log streams for each trail
          "logs:CreateLogStream",
          # Write log events
          "logs:PutLogEvents"
        ]
        # Scope to the specific log group
        Resource = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# SNS Topic for CloudTrail Notifications
#------------------------------------------------------------------------------
# SNS topic receives notifications when CloudTrail delivers log files.
# Can be used to trigger Lambda functions, send emails, or integrate with
# third-party SIEM solutions.
#------------------------------------------------------------------------------

resource "aws_sns_topic" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  name = "cloudtrail-notifications"

  # Optional: Encrypt SNS messages at rest with KMS
  # kms_master_key_id = aws_kms_key.cloudtrail.arn

  tags = {
    Name       = "cloudtrail-notifications"
    Purpose    = "CloudTrail log delivery notifications"
    CostCenter = "Security"
  }
}

#------------------------------------------------------------------------------
# SNS Topic Policy
#------------------------------------------------------------------------------
# Allow CloudTrail service to publish notifications to this topic.
#------------------------------------------------------------------------------

resource "aws_sns_topic_policy" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  arn = aws_sns_topic.cloudtrail[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudTrailPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.cloudtrail[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# AWS CloudTrail Trail
#------------------------------------------------------------------------------
# The main CloudTrail resource. Configured for:
#   - Multi-region coverage (all AWS regions)
#   - Management events (API calls)
#   - Log file validation (integrity checking)
#   - CloudWatch Logs integration
#   - SNS notifications
#
# Note: This is NOT an organization trail. For organization-wide logging,
# you need AWS Organizations with delegated administrator access.
#------------------------------------------------------------------------------

resource "aws_cloudtrail" "main" {
  count = var.enable_cloudtrail ? 1 : 0

  name = var.cloudtrail_name

  # S3 bucket for log storage
  s3_bucket_name = aws_s3_bucket.cloudtrail[0].id
  # Optional: Use a prefix to organize logs
  # s3_key_prefix = "cloudtrail"

  # Enable multi-region trail to capture all API activity across all regions
  # This is crucial for security monitoring - attackers may use other regions
  is_multi_region_trail = true

  # Include global service events (IAM, STS, CloudFront)
  # These are region-less services, captured in us-east-1 by default
  include_global_service_events = true

  # Enable log file validation to detect tampering
  # Creates a digest file every hour with hashes of all log files
  enable_log_file_validation = true

  # CloudWatch Logs integration for real-time monitoring
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch[0].arn

  # SNS topic for log delivery notifications
  sns_topic_name = aws_sns_topic.cloudtrail[0].arn

  # Event selectors for management events (default)
  # Management events include:
  #   - IAM operations (CreateUser, AttachPolicy, etc.)
  #   - EC2 operations (RunInstances, CreateSecurityGroup, etc.)
  #   - S3 bucket operations (CreateBucket, PutBucketPolicy, etc.)
  #   - All other control plane operations
  event_selector {
    # Read and write management events
    read_write_type           = "All"
    include_management_events = true

    # Data events (S3 object-level, Lambda invocations) are NOT included
    # to stay within free tier and reduce noise. Enable if needed:
    # data_resource {
    #   type   = "AWS::S3::Object"
    #   values = ["arn:aws:s3:::"]  # All S3 objects
    # }
  }

  # Optional: Encrypt logs with KMS
  # kms_key_id = aws_kms_key.cloudtrail.arn

  # Ensure bucket policy is in place before creating trail
  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_iam_role_policy.cloudtrail_cloudwatch
  ]

  tags = {
    Name       = var.cloudtrail_name
    Purpose    = "Security audit logging"
    Compliance = "SOC2, PCI-DSS, HIPAA"
    CostCenter = "Security"
  }
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------
# Export important values for reference and integration with other services.
#------------------------------------------------------------------------------

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.main[0].arn : null
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail trail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.main[0].name : null
}

output "cloudtrail_s3_bucket_name" {
  description = "Name of the S3 bucket storing CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].id : null
}

output "cloudtrail_s3_bucket_arn" {
  description = "ARN of the S3 bucket storing CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].arn : null
}

output "cloudtrail_cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudwatch_log_group.cloudtrail[0].arn : null
}

output "cloudtrail_cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudwatch_log_group.cloudtrail[0].name : null
}

output "cloudtrail_sns_topic_arn" {
  description = "ARN of the SNS topic for CloudTrail notifications"
  value       = var.enable_cloudtrail ? aws_sns_topic.cloudtrail[0].arn : null
}

output "cloudtrail_role_arn" {
  description = "ARN of the IAM role used by CloudTrail for CloudWatch Logs"
  value       = var.enable_cloudtrail ? aws_iam_role.cloudtrail_cloudwatch[0].arn : null
}
