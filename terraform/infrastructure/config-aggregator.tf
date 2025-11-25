# ==============================================================================
# AWS Config Aggregator
# ==============================================================================
# Aggregates AWS Config data from all accounts in the organization into sec-tools
# This enables centralized compliance monitoring and security posture management

# IAM role for Config Aggregator
resource "aws_iam_role" "config_aggregator" {
  name = "AWSConfigAggregatorRole"

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
    Name      = "AWS Config Aggregator Role"
    Purpose   = "Aggregate Config data across organization"
    Component = "Compliance"
  }
}

# Attach managed policy for Config aggregator
resource "aws_iam_role_policy_attachment" "config_aggregator" {
  role       = aws_iam_role.config_aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

# Organization-wide Config Aggregator
# NOTE: This must be deployed in the sec-tools account (183590991623)
resource "aws_config_configuration_aggregator" "organization" {
  name = "organization-aggregator"

  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.config_aggregator.arn
  }

  tags = {
    Name      = "Organization Config Aggregator"
    Purpose   = "Centralized compliance monitoring"
    Component = "Security"
    Account   = "sec-tools"
  }
}

# ==============================================================================
# Outputs
# ==============================================================================

output "config_aggregator_arn" {
  description = "ARN of the AWS Config aggregator"
  value       = aws_config_configuration_aggregator.organization.arn
}

output "config_aggregator_name" {
  description = "Name of the AWS Config aggregator"
  value       = aws_config_configuration_aggregator.organization.name
}
