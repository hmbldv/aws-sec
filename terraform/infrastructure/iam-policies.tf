# =============================================================================
# Custom IAM Policies
# =============================================================================

# -----------------------------------------------------------------------------
# MyIAM-ReadOnlyPerms Policy
# Import: terraform import aws_iam_policy.iam_readonly arn:aws:iam::<account-id>:policy/MyIAM-ReadOnlyPerms
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "iam_readonly" {
  name = "MyIAM-ReadOnlyPerms"
  path = "/"
  # Note: description not set to match existing policy

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VisualEditor0" # Matches existing policy
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:GetUser"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "IAM Read-Only Permissions"
    Purpose     = "Limited IAM enumeration for security testing"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Security Analyst Role (for IAM Identity Center users)
# This role can be assumed by users from IAM Identity Center
# -----------------------------------------------------------------------------

resource "aws_iam_role" "security_analyst" {
  name        = "SecurityAnalyst"
  description = "Role for security analysts with read access and security tool permissions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::${var.aws_account_id}:role/aws-reserved/sso.amazonaws.com/*"
          }
        }
      }
    ]
  })

  max_session_duration = 14400 # 4 hours

  tags = {
    Name        = "Security Analyst Role"
    Purpose     = "Security analysis and testing"
    Environment = var.environment
  }
}

# Security Analyst - Read-only access to most services
resource "aws_iam_role_policy_attachment" "security_analyst_readonly" {
  role       = aws_iam_role.security_analyst.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Security Analyst - Security Hub access
resource "aws_iam_role_policy_attachment" "security_analyst_securityhub" {
  role       = aws_iam_role.security_analyst.name
  policy_arn = "arn:aws:iam::aws:policy/AWSSecurityHubFullAccess"
}

# Security Analyst - GuardDuty read access
resource "aws_iam_role_policy_attachment" "security_analyst_guardduty" {
  role       = aws_iam_role.security_analyst.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonGuardDutyReadOnlyAccess"
}

# Security Analyst - Inspector access
resource "aws_iam_role_policy_attachment" "security_analyst_inspector" {
  role       = aws_iam_role.security_analyst.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonInspector2ReadOnlyAccess"
}

# Security Analyst - CloudTrail access
resource "aws_iam_role_policy_attachment" "security_analyst_cloudtrail" {
  role       = aws_iam_role.security_analyst.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCloudTrail_ReadOnlyAccess"
}

# Custom policy for security analyst EC2 access (for lab management)
resource "aws_iam_policy" "security_analyst_ec2" {
  name        = "SecurityAnalyst-EC2Management"
  description = "Allows security analysts to manage security lab EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2LabManagement"
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:RebootInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Lab" = "security-lab"
          }
        }
      },
      {
        Sid    = "EC2DescribeAll"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMSessionManager"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:DescribeSessions",
          "ssm:GetConnectionStatus"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name    = "Security Analyst EC2 Management"
    Purpose = "Lab instance control"
  }
}

resource "aws_iam_role_policy_attachment" "security_analyst_ec2" {
  role       = aws_iam_role.security_analyst.name
  policy_arn = aws_iam_policy.security_analyst_ec2.arn
}

# -----------------------------------------------------------------------------
# Cross-Account Access Role (for organization management)
# Allows admin access from IAM Identity Center
# -----------------------------------------------------------------------------

resource "aws_iam_role" "organization_admin" {
  name        = "OrganizationAdmin"
  description = "Cross-account admin role for organization management via IAM Identity Center"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::${var.aws_account_id}:role/aws-reserved/sso.amazonaws.com/*"
          }
        }
      }
    ]
  })

  max_session_duration = 14400 # 4 hours

  tags = {
    Name        = "Organization Admin Role"
    Purpose     = "Cross-account organization administration"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "organization_admin" {
  role       = aws_iam_role.organization_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "iam_readonly_policy_arn" {
  description = "ARN of the IAM read-only policy"
  value       = aws_iam_policy.iam_readonly.arn
}

output "security_analyst_role_arn" {
  description = "ARN of the Security Analyst role"
  value       = aws_iam_role.security_analyst.arn
}

output "organization_admin_role_arn" {
  description = "ARN of the Organization Admin role"
  value       = aws_iam_role.organization_admin.arn
}
