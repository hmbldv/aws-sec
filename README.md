# AWS Security Infrastructure

Secure AWS infrastructure foundation built with Terraform, featuring remote state management and GitLab CI/CD automation with OIDC federation.

## Overview

This project establishes a production-grade foundation for AWS security infrastructure using Infrastructure as Code (IaC) principles. It implements secure Terraform state management with S3 and DynamoDB, and integrates with GitLab CI/CD using OpenID Connect (OIDC) for credential-less AWS authentication.

**Key Features**:
- **Security Testing Lab**: Ubuntu target + attacker instances with Kali tools for offensive/defensive testing
- **Multi-Account Management**: IAM roles for cross-account access via IAM Identity Center
- **Secure State Management**: Encrypted S3 backend with versioning and lifecycle policies
- **State Locking**: DynamoDB table preventing concurrent Terraform executions
- **Zero Credential Storage**: OIDC federation for GitLab → AWS authentication
- **Security Monitoring**: AWS Config and Macie bucket integration
- **Cost Optimized**: Pay-per-request DynamoDB, intelligent S3 lifecycle policies
- **Security First**: IMDSv2 required, encrypted EBS, public access blocked

## Tech Stack

- **Terraform** - Infrastructure as Code for AWS resource provisioning
- **AWS EC2** - Security lab instances (Ubuntu target + attacker with Kali tools)
- **AWS S3** - Encrypted remote state storage, AWS Config, and Macie buckets
- **AWS DynamoDB** - State locking and consistency management
- **AWS IAM** - OIDC identity provider, security analyst roles, cross-account access
- **AWS SSM** - Session Manager for secure instance access
- **GitLab CI/CD** - Automated infrastructure deployment pipeline

## Architecture

### Security Lab Architecture

```
                    ┌─────────────────┐
                    │   Your Admin    │
                    │   Workstation   │
                    └────────┬────────┘
                             │ SSH/RDP/SSM
                             ▼
┌────────────────────────────────────────────────────────────┐
│                     AWS VPC (172.31.0.0/16)                │
│  ┌─────────────────────┐     ┌─────────────────────────┐  │
│  │   Attacker Box      │     │     Ubuntu Target       │  │
│  │   (Ubuntu + Kali)   │────▶│     (t3.medium)         │  │
│  │                     │     │                         │  │
│  │ - Metasploit        │ ALL │ - Ubuntu Desktop        │  │
│  │ - Nmap, Hydra       │PORTS│ - Apache, MySQL         │  │
│  │ - Impacket, CrackME │     │ - XRDP for remote       │  │
│  │ - SecLists, PEASS   │     │ - Vulnerable services   │  │
│  └─────────────────────┘     └─────────────────────────┘  │
│     SG: kali-attacker           SG: ubuntu-target         │
└────────────────────────────────────────────────────────────┘
```

**Security Features:**
- IMDSv2 required (prevents SSRF credential theft)
- Encrypted EBS volumes
- SSM Session Manager enabled
- CloudWatch detailed monitoring

### Infrastructure State Management

```
┌─────────────────┐
│  GitLab CI/CD   │
│   (OIDC Token)  │
└────────┬────────┘
         │ Assume Role (OIDC)
         ▼
┌─────────────────────────┐
│    AWS IAM Role         │
│  "devops-operator"      │
│  (Restricted by Path)   │
└────────┬────────────────┘
         │
         ├──────────────┐
         │              │
         ▼              ▼
┌──────────────┐  ┌─────────────────┐
│  S3 Bucket   │  │ DynamoDB Table  │
│ (State File) │  │ (State Locks)   │
│  Encrypted   │  │  "LockID" Key   │
│  Versioned   │  │  PAY_PER_REQ    │
└──────────────┘  └─────────────────┘
```

### Security Architecture

- **Encryption at Rest**: S3 server-side encryption (AES256)
- **Access Control**: IAM role with project path restrictions
- **Public Access**: Completely blocked via S3 bucket policies
- **State Integrity**: DynamoDB locking prevents state corruption
- **Audit Trail**: S3 versioning enables state history and rollback
- **Credential-less**: OIDC eliminates need for long-lived AWS credentials

## Prerequisites

### Required Tools
- **Terraform** >= 1.0
- **AWS CLI** v2 (for manual operations)
- **GitLab Account** with OIDC configured

### AWS Account Requirements
- AWS account with administrative access (for initial setup)
- IAM permissions to create:
  - S3 buckets
  - DynamoDB tables
  - IAM roles and policies
  - OIDC identity providers

### GitLab Setup
- GitLab project repository
- OIDC identity provider configured in AWS
- IAM role with trust policy for GitLab project path

## Installation

### Step 1: Clone Repository

```bash
git clone https://gitlab.com/username/aws-sec.git
cd aws-sec
```

### Step 2: Configure Variables

Edit `terraform/state-backend/variables.tf` or create `terraform.tfvars`:

```hcl
aws_account_id      = "123456789012"  # Your AWS account ID
aws_region          = "us-west-1"
state_bucket_name   = ""              # Auto-generated if empty
dynamodb_table_name = "terraform-state-locks"
```

### Step 3: Initialize Terraform State Backend

**Important**: This must be done locally first, before GitLab CI/CD can use it.

```bash
cd terraform/state-backend

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply to create S3 bucket and DynamoDB table
terraform apply
```

**Output** (save these values):
```
state_bucket_name   = "terraform-state-123456789012-us-west-1"
dynamodb_table_name = "terraform-state-locks"
state_bucket_arn    = "arn:aws:s3:::terraform-state-..."
```

### Step 4: Configure Backend for Future Infrastructure

Create `terraform/infrastructure/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-123456789012-us-west-1"  # From Step 3
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-1"
    dynamodb_table = "terraform-state-locks"                   # From Step 3
    encrypt        = true
  }
}
```

## Configuration

### GitLab CI/CD Pipeline

The `.gitlab-ci.yml` pipeline:
1. Authenticates to AWS using OIDC (no stored credentials)
2. Assumes the `devops-operator` IAM role
3. Runs Terraform commands with temporary credentials

**Current Pipeline Stages**:
- `test` - Validates AWS authentication

**Future Pipeline Stages** (to be implemented):
- `validate` - Terraform fmt and validate
- `plan` - Terraform plan on merge requests
- `apply` - Terraform apply on main branch
- `security` - tfsec security scanning

### IAM Role Configuration

The `devops-operator` role requires this trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/gitlab.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "gitlab.com:aud": "https://gitlab.com"
        },
        "StringLike": {
          "gitlab.com:sub": "project_path:username/aws-sec:*"
        }
      }
    }
  ]
}
```

**Security Note**: The `project_path` condition restricts this role to only this GitLab project.

## Usage

### Local Terraform Operations

```bash
# Authenticate to AWS
aws sso login --profile <your-profile>

# Navigate to infrastructure directory
cd terraform/infrastructure

# Initialize (uses remote backend)
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply
```

### GitLab CI/CD Operations

**Automatic Execution**:
- Push to `main` branch triggers the pipeline
- OIDC authentication happens automatically
- No manual AWS credential management needed

**Manual Pipeline Trigger**:
1. Go to GitLab project → CI/CD → Pipelines
2. Click "Run Pipeline"
3. Select branch and run

## Deployment

### Current State
- ✅ State backend deployed (S3 + DynamoDB)
- ✅ GitLab OIDC authentication working
- ✅ Security lab deployed (Ubuntu target + attacker with Kali tools)
- ✅ IAM roles created (SecurityAnalyst, OrganizationAdmin)
- ✅ S3 buckets managed (AWS Config, Macie)
- ⏳ Multi-account scanning (Log Archive access pending)

### Security Lab Access

**SSH Access:**
```bash
# Attacker box (Ubuntu + Kali tools)
ssh -i ~/.ssh/id_ed25519 ubuntu@<attacker-public-ip>

# Target box
ssh -i ~/.ssh/id_ed25519 ubuntu@<target-public-ip>
```

**RDP Access (after user-data completes):**
- Attacker: `<attacker-public-ip>:3389` (user: `pentester` / pass: `KaliPentester123!`)
- Target: `<target-public-ip>:3389` (user: `labuser` / pass: `LabPassword123!`)

**SSM Session Manager:**
```bash
aws ssm start-session --target <instance-id>
```

### Next Steps
1. Expand GitLab CI/CD pipeline with Terraform stages
2. Fix Log Archive account access (OrganizationAccountAccessRole)
3. Implement security scanning (tfsec, checkov)
4. Add GuardDuty, Security Hub, CloudTrail

## Security Considerations

### State Security
- **Encryption**: All state files encrypted at rest with AES256
- **Access Control**: S3 bucket is private, no public access
- **Versioning**: Enabled for audit trail and rollback capability
- **Lifecycle Management**: Old state versions archived and expired

### Credential Security
- **No Stored Credentials**: OIDC federation eliminates long-lived access keys
- **Temporary Credentials**: STS provides short-lived credentials (1 hour)
- **Least Privilege**: IAM role restricted to specific GitLab project path
- **Audit Trail**: CloudTrail logs all API calls made by the role

### Operational Security Best Practices
1. **Never commit credentials** to Git (use `.gitignore`)
2. **Review Terraform plans** before applying
3. **Use workspaces** for environment isolation
4. **Enable MFA** for AWS console access
5. **Rotate credentials** regularly (even though OIDC minimizes this need)
6. **Monitor costs** to detect unexpected resource creation

## Project Structure

```
aws-sec/
├── terraform/
│   ├── state-backend/          # Remote state infrastructure
│   │   ├── main.tf             # S3 bucket and DynamoDB table
│   │   ├── variables.tf        # Input variables
│   │   ├── outputs.tf          # Output values
│   │   └── providers.tf        # AWS provider configuration
│   │
│   └── infrastructure/         # Main infrastructure code
│       ├── security-lab.tf     # EC2 instances (target + attacker)
│       ├── iam-policies.tf     # SecurityAnalyst, OrganizationAdmin roles
│       ├── s3-buckets.tf       # AWS Config and Macie bucket management
│       ├── oidc.tf             # GitLab OIDC provider and devops role
│       ├── variables.tf        # Input variables
│       └── providers.tf        # AWS provider and S3 backend
│
├── scripts/                    # Automation scripts
├── docs/                       # Additional documentation
├── .gitlab-ci.yml              # GitLab CI/CD pipeline
├── .gitignore                  # Excludes sensitive files
└── README.md                   # This file
```

## Troubleshooting

### Issue: "Error acquiring state lock"

**Cause**: Previous Terraform run was interrupted, leaving a stale lock

**Solution**:
```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>

# Or check DynamoDB table for active locks
aws dynamodb scan --table-name terraform-state-locks
```

### Issue: GitLab CI/CD fails with "AccessDenied"

**Possible Causes**:
1. OIDC identity provider not configured in AWS
2. IAM role trust policy incorrect
3. Project path in trust policy doesn't match

**Solution**:
- Verify OIDC provider exists: `aws iam list-open-id-connect-providers`
- Check IAM role trust policy matches your GitLab project path
- Ensure role has necessary permissions

### Issue: "bucket already exists"

**Cause**: S3 bucket names must be globally unique

**Solution**:
- Let Terraform auto-generate the bucket name (leave `state_bucket_name` empty)
- Or choose a more unique bucket name with your AWS account ID

## Future Enhancements

### Completed
- [x] Security testing lab (Ubuntu target + attacker)
- [x] IAM roles for security analysts
- [x] S3 bucket management (Config, Macie)
- [x] GitLab OIDC integration
- [x] IMDSv2 enforcement on EC2

### Planned Infrastructure
- [ ] VPC with public/private subnets (dedicated security lab VPC)
- [ ] AWS GuardDuty for threat detection
- [ ] Security Hub for centralized findings
- [ ] CloudTrail for audit logging
- [ ] Config rules for compliance monitoring
- [ ] KMS keys for encryption

### Pipeline Enhancements
- [ ] Terraform plan on merge requests
- [ ] Automated security scanning (tfsec, checkov)
- [ ] Cost estimation (Infracost)
- [ ] Automated testing
- [ ] Slack/SNS notifications

### Security Enhancements
- [ ] Customer-managed KMS keys for S3 encryption
- [ ] MFA delete for S3 bucket
- [ ] S3 bucket logging
- [ ] VPC endpoints for S3 access
- [ ] Secrets management with AWS Secrets Manager
- [ ] Restrict security lab to specific CIDR blocks

## Cost Optimization

**Current Costs** (estimated):
- **EC2 (t3.medium x2)**: ~$60/month (if running 24/7) - **stop when not in use!**
- **EBS Storage (90GB)**: ~$7/month
- **S3 Storage**: ~$0.023/GB/month (Standard tier)
- **S3 Requests**: Minimal (PUT/GET for state operations)
- **DynamoDB**: ~$0.25/million requests (PAY_PER_REQUEST mode)
- **Data Transfer**: Free within same region

**Cost-Saving Tips**:
- **Stop EC2 instances** when not actively testing (biggest savings!)
- State versions moved to STANDARD_IA after 30 days (~50% cheaper)
- Old versions deleted after 90 days
- DynamoDB on-demand pricing (no idle costs)
- No KMS charges (using AWS-managed keys)

**Estimated Monthly Cost**:
- With EC2 running: ~$70/month
- With EC2 stopped: < $10/month

## License

MIT

## Author

Johnny Endrihs
- GitHub: [hmbldv](https://github.com/hmbldv)
- GitLab: [username](https://gitlab.com/username)

---

**Built as part of DevSecOps portfolio** demonstrating:
- Infrastructure as Code (Terraform)
- AWS Security Best Practices
- CI/CD Automation (GitLab)
- Secure State Management
- OIDC Federation
- Cost Optimization

*Preparing for AWS Certified Security - Specialty*
