variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
  default     = "" # Set via terraform.tfvars
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "production"
}

variable "gitlab_project_path" {
  description = "GitLab project path for OIDC authentication"
  type        = string
  default     = "" # Set via terraform.tfvars (e.g., "username/project")
}

# =============================================================================
# Security Lab Variables
# =============================================================================

variable "ssh_public_key" {
  description = "SSH public key for EC2 instance access"
  type        = string
  default     = "" # Set via terraform.tfvars (your SSH public key)
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
  default = {} # Set via terraform.tfvars for multi-account access
}
