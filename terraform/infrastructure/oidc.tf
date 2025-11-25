# GitLab OIDC Provider for credential-less authentication
resource "aws_iam_openid_connect_provider" "gitlab" {
  url = "https://gitlab.com"

  client_id_list = [
    "https://gitlab.com",
  ]

  # GitLab's OIDC thumbprints (current as of Nov 2024)
  thumbprint_list = [
    "2b8f1b57330dbba2d07a6c51f70ee90ddab9ad8e",
  ]

  tags = {
    Name        = "GitLab OIDC Provider"
    ManagedBy   = "Terraform"
    Environment = "production"
    Purpose     = "GitLab CI/CD authentication"
  }
}

# DevOps operator role for GitLab CI/CD pipeline
resource "aws_iam_role" "devops_operator" {
  name        = "devops-operator"
  path        = "/"
  description = "Role for GitLab CI/CD pipeline to deploy infrastructure via Terraform"

  max_session_duration = 3600 # 1 hour

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.gitlab.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "gitlab.com:aud" = "https://gitlab.com"
          }
          StringLike = {
            # Restrict to specific GitLab project and branches
            "gitlab.com:sub" = "project_path:${var.gitlab_project_path}:ref_type:branch:ref:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "DevOps Operator"
    ManagedBy   = "Terraform"
    Environment = "production"
    Purpose     = "GitLab CI/CD deployment"
  }
}

# Attach AdministratorAccess policy to devops-operator role
# WARNING: This grants full AWS access. Consider least-privilege alternatives.
resource "aws_iam_role_policy_attachment" "devops_operator_admin" {
  role       = aws_iam_role.devops_operator.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Output the role ARN for GitLab CI/CD configuration
output "devops_operator_role_arn" {
  description = "ARN of the DevOps operator role for GitLab CI/CD"
  value       = aws_iam_role.devops_operator.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitLab OIDC provider"
  value       = aws_iam_openid_connect_provider.gitlab.arn
}
