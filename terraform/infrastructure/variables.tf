variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
  default     = "123456789012"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "production"
}

variable "gitlab_project_path" {
  description = "GitLab project path for OIDC authentication"
  type        = string
  default     = "username/aws-sec"
}

# =============================================================================
# Security Lab Variables
# =============================================================================

variable "ssh_public_key" {
  description = "SSH public key for EC2 instance access"
  type        = string
  default     = "ssh-ed25519 AAAA...your-key-here user@example.com"
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed to access lab machines (your IP)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # CHANGE THIS to your actual IP for security!
  # Example: ["203.0.113.42/32"] for a single IP
}

variable "security_lab_instance_type" {
  description = "Instance type for security lab machines"
  type        = string
  default     = "t3.medium" # Recommended for desktop/GUI usage
}

# =============================================================================
# Multi-Account Configuration
# =============================================================================

variable "organization_accounts" {
  description = "Map of AWS organization accounts"
  type = map(object({
    account_id = string
    role_name  = string
  }))
  default = {
    squinks = {
      account_id = "123456789012"
      role_name  = "OrganizationAccountAccessRole"
    }
    container_services = {
      account_id = "234567890123"
      role_name  = "OrganizationAccountAccessRole"
    }
    log_archive = {
      account_id = "345678901234"
      role_name  = "OrganizationAccountAccessRole"
    }
    sec_tools = {
      account_id = "456789012345"
      role_name  = "OrganizationAccountAccessRole"
    }
  }
}
