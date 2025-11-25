# ==============================================================================
# AWS Config Recorder (Deploy in each source account)
# ==============================================================================
# Enables AWS Config recording in the account
# This is required before the aggregator can collect data from this account
# NOTE: Config bucket is defined in s3-buckets.tf

# IAM role for Config recorder
resource "aws_iam_role" "config_recorder" {
  name = "AWSConfigRecorderRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "config.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name      = "AWS Config Recorder Role"
    Purpose   = "Record AWS resource configurations"
    Component = "Compliance"
  }
}

# Attach AWS managed policy for Config recorder
resource "aws_iam_role_policy_attachment" "config_recorder_managed" {
  role       = aws_iam_role.config_recorder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# IAM policy for Config recorder permissions
# Grant permissions to record AWS resource configurations
resource "aws_iam_role_policy" "config_permissions" {
  name = "AWSConfigRecorderPolicy"
  role = aws_iam_role.config_recorder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "config:Put*",
          "cloudwatch:PutMetricData",
          # Permissions for all AWS services that Config monitors
          "ec2:Describe*",
          "elasticloadbalancing:Describe*",
          "autoscaling:Describe*",
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrailStatus",
          "cloudwatch:Describe*",
          "rds:Describe*",
          "rds:ListTagsForResource",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:GetUser",
          "iam:GetUserPolicy",
          "iam:GetGroup",
          "iam:GetGroupPolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListUserPolicies",
          "iam:ListAttachedUserPolicies",
          "iam:ListGroupPolicies",
          "iam:ListAttachedGroupPolicies",
          "iam:ListPolicies",
          "iam:ListPolicyVersions",
          "iam:ListEntitiesForPolicy",
          "s3:GetObject",
          "s3:GetBucketPolicy",
          "s3:GetBucketVersioning",
          "s3:GetBucketAcl",
          "s3:GetBucketLogging",
          "s3:GetBucketLocation",
          "s3:GetBucketTagging",
          "s3:GetEncryptionConfiguration",
          "s3:GetBucketPublicAccessBlock",
          "s3:ListBucket",
          "s3:ListAllMyBuckets",
          "lambda:GetFunction",
          "lambda:GetPolicy",
          "lambda:ListFunctions",
          "sns:GetTopicAttributes",
          "sns:ListTopics",
          "sqs:GetQueueAttributes",
          "sqs:ListQueues",
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListKeys",
          "dynamodb:DescribeTable",
          "dynamodb:ListTables",
          "tag:GetResources",
          "tag:GetTagKeys",
          "tag:GetTagValues"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for S3 bucket access
resource "aws_iam_role_policy" "config_s3" {
  name = "AWSConfigS3Policy"
  role = aws_iam_role.config_recorder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ]
      Resource = "${aws_s3_bucket.config_bucket.arn}/*"
      Condition = {
        StringEquals = {
          "s3:x-amz-acl" = "bucket-owner-full-control"
        }
      }
      }, {
      Effect = "Allow"
      Action = [
        "s3:GetBucketAcl",
        "s3:ListBucket"
      ]
      Resource = aws_s3_bucket.config_bucket.arn
    }]
  })
}

# Config recorder
resource "aws_config_configuration_recorder" "main" {
  name     = "default"
  role_arn = aws_iam_role.config_recorder.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

# Config delivery channel
resource "aws_config_delivery_channel" "main" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket

  depends_on = [aws_config_configuration_recorder.main]
}

# Start the recorder
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# ==============================================================================
# Outputs
# ==============================================================================

output "config_recorder_name" {
  description = "Name of the Config recorder"
  value       = aws_config_configuration_recorder.main.name
}

output "config_recorder_role_arn" {
  description = "ARN of the Config recorder IAM role"
  value       = aws_iam_role.config_recorder.arn
}

output "config_delivery_channel_name" {
  description = "Name of the Config delivery channel"
  value       = aws_config_delivery_channel.main.name
}
