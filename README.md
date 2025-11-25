# AWS Security Infrastructure

Secure AWS infrastructure foundation built with Terraform, featuring AWS Config aggregator for organization-wide compliance monitoring and security testing lab environments.

## Overview

This project establishes a production-grade foundation for AWS security infrastructure using Infrastructure as Code (IaC) principles. It implements comprehensive security monitoring with AWS Config, IAM security roles, and a hands-on security testing laboratory.

**Key Features**:
- **AWS Config Aggregator**: Organization-wide compliance monitoring across all AWS accounts and regions
- **Security Testing Lab**: Ubuntu target + attacker instances with Kali tools for offensive/defensive testing
- **Multi-Account Management**: IAM roles for cross-account access via IAM Identity Center
- **Configuration Recording**: Continuous tracking of all AWS resource configurations
- **Security Monitoring**: AWS Config recorder, Config aggregator, and Macie integration
- **Local State Management**: Simplified Terraform state management for rapid iteration
- **Security First**: IMDSv2 required, encrypted EBS, public access blocked on S3 buckets

## Tech Stack

- **Terraform** - Infrastructure as Code for AWS resource provisioning
- **AWS Config** - Resource configuration recording and organization-wide aggregation
- **AWS EC2** - Security lab instances (Ubuntu target + attacker with Kali tools)
- **AWS S3** - Encrypted storage for AWS Config snapshots and Macie findings
- **AWS IAM** - Security analyst roles, Config recorder roles, cross-account access
- **AWS SSM** - Session Manager for secure instance access
- **AWS Macie** - Sensitive data discovery and classification

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

### AWS Config Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                   AWS Organization                             │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │   Account    │  │   Account    │  │   Account    │        │
│  │   (squinks)  │  │ (sec-tools)  │  │(log-archive) │  ...   │
│  │              │  │              │  │              │        │
│  │ Config       │  │ Config       │  │ Config       │        │
│  │ Recorder     │  │ Recorder     │  │ Recorder     │        │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │
│         │                 │                 │                 │
│         └─────────────────┼─────────────────┘                 │
│                           ▼                                    │
│                ┌────────────────────────┐                      │
│                │   Config Aggregator    │                      │
│                │  (organization-wide)   │                      │
│                │   All Regions          │                      │
│                └────────┬───────────────┘                      │
│                         │                                      │
│                         ▼                                      │
│                ┌─────────────────┐                             │
│                │  S3 Bucket      │                             │
│                │  (Config Data)  │                             │
│                │  Encrypted      │                             │
│                └─────────────────┘                             │
└────────────────────────────────────────────────────────────────┘
```

**Config Features:**
- **Continuous Recording**: Tracks all resource configuration changes
- **Organization Aggregation**: Centralized view across all AWS accounts
- **All Regions**: Monitors resources in every AWS region
- **Compliance Monitoring**: Enables compliance rules and auditing
- **7-Year Retention**: Config snapshots retained for compliance requirements

### Security Architecture

- **Encryption at Rest**: S3 server-side encryption (AES256) for Config data
- **Access Control**: IAM service roles with least privilege permissions
- **Public Access**: Completely blocked via S3 bucket policies
- **Audit Trail**: S3 versioning and lifecycle policies for Config snapshots
- **Compliance**: Continuous monitoring of resource configurations

## Prerequisites

### Required Tools
- **Terraform** >= 1.0
- **AWS CLI** v2 with SSO configured
- **SSH Key** for EC2 instance access

### AWS Account Requirements
- AWS Organizations with multiple accounts (recommended)
- IAM permissions to create:
  - EC2 instances and security groups
  - IAM roles and policies
  - AWS Config recorder and aggregator
  - S3 buckets for Config and Macie
- AWS IAM Identity Center (SSO) access

## Installation

### Step 1: Clone Repository

```bash
git clone https://github.com/hmbldv/aws-sec.git
cd aws-sec
```

### Step 2: Configure Variables

Edit the Terraform variables file:

```bash
cd terraform/infrastructure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Example `terraform.tfvars`:
```hcl
aws_account_id      = "123456789012"  # Your AWS account ID
aws_region          = "us-west-1"
environment         = "production"
ssh_public_key      = "ssh-ed25519 AAAA..."  # Your SSH public key
admin_cidr_blocks   = ["YOUR_IP/32"]  # Restrict to your IP
```

### Step 3: Deploy Infrastructure

```bash
# Authenticate to AWS
aws sso login --profile default

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply to create all resources
terraform apply
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
          "gitlab.com:sub": "project_path:<your-gitlab-username>/<project>:*"
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

# Initialize with local backend
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
- ✅ AWS Config aggregator deployed (organization-wide)
- ✅ AWS Config recorder running (continuous monitoring)
- ✅ Security lab deployed (Ubuntu target + attacker with Kali tools)
- ✅ IAM roles created (SecurityAnalyst, OrganizationAdmin)
- ✅ S3 buckets managed (AWS Config, Macie)
- ✅ GitLab OIDC authentication working
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
1. Deploy Config recorders in other organization accounts
2. Expand GitLab CI/CD pipeline with Terraform stages
3. Implement security scanning (tfsec, checkov)
4. Add GuardDuty, Security Hub, CloudTrail

## Security Considerations

### Infrastructure Security
- **Encryption**: All S3 buckets use AES256 server-side encryption
- **Access Control**: S3 buckets are private with explicit deny policies
- **IMDSv2**: Required on all EC2 instances to prevent SSRF attacks
- **EBS Encryption**: All volumes encrypted at rest
- **Network Security**: Security groups with principle of least privilege

### Credential Security
- **No Stored Credentials**: OIDC federation eliminates long-lived access keys
- **Temporary Credentials**: STS provides short-lived credentials (1 hour)
- **Least Privilege**: IAM roles restricted to specific GitLab project path
- **Audit Trail**: CloudTrail logs all API calls made by roles

### Operational Security Best Practices
1. **Never commit credentials** to Git (use `.gitignore`)
2. **Review Terraform plans** before applying
3. **Enable MFA** for AWS console access
4. **Monitor costs** to detect unexpected resource creation
5. **Stop EC2 instances** when not in use (biggest cost savings)
6. **Restrict CIDR blocks** to your actual IP addresses

## Project Structure

```
aws-sec/
├── terraform/
│   └── infrastructure/         # Main infrastructure code
│       ├── config-aggregator.tf    # AWS Config aggregator
│       ├── config-recorder.tf      # AWS Config recorder
│       ├── security-lab.tf         # EC2 instances (target + attacker)
│       ├── iam-policies.tf         # SecurityAnalyst, OrganizationAdmin roles
│       ├── s3-buckets.tf           # AWS Config and Macie bucket management
│       ├── oidc.tf                 # GitLab OIDC provider and devops role
│       ├── variables.tf            # Input variables
│       └── providers.tf            # AWS provider configuration
│
├── docs/                       # Additional documentation
│   └── config-aggregator-setup.md  # Config aggregator deployment guide
│
├── scripts/                    # Automation scripts
├── .gitlab-ci.yml              # GitLab CI/CD pipeline
├── .gitignore                  # Excludes sensitive files
└── README.md                   # This file
```

## Troubleshooting

### Issue: GitLab CI/CD fails with "AccessDenied"

**Possible Causes**:
1. OIDC identity provider not configured in AWS
2. IAM role trust policy incorrect
3. Project path in trust policy doesn't match

**Solution**:
- Verify OIDC provider exists: `aws iam list-open-id-connect-providers`
- Check IAM role trust policy matches your GitLab project path
- Ensure role has necessary permissions

### Issue: Config recorder not recording

**Solution**:
```bash
# Check recorder status
aws configservice describe-configuration-recorder-status

# Check delivery channel
aws configservice describe-delivery-channels

# Verify S3 bucket permissions
aws s3api get-bucket-policy --bucket config-bucket-<account-id>
```

### Issue: EC2 instances not accessible

**Possible Causes**:
1. Security group doesn't allow your IP
2. User data script still running
3. SSH key mismatch

**Solution**:
- Update `admin_cidr_blocks` in terraform.tfvars with your actual IP
- Wait 5-10 minutes for user data to complete
- Verify SSH key matches the one configured in terraform.tfvars

## Future Enhancements

### Completed
- [x] AWS Config aggregator (organization-wide)
- [x] AWS Config recorder (continuous monitoring)
- [x] Security testing lab (Ubuntu target + attacker)
- [x] IAM roles for security analysts
- [x] S3 bucket management (Config, Macie)
- [x] GitLab OIDC integration
- [x] IMDSv2 enforcement on EC2

### Planned Infrastructure
- [ ] Deploy Config recorders in all organization accounts
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
- [ ] MFA delete for S3 buckets
- [ ] S3 bucket logging
- [ ] VPC endpoints for S3 access
- [ ] Secrets management with AWS Secrets Manager

## Cost Optimization

**Current Costs** (estimated):
- **EC2 (t3.medium x2)**: ~$60/month (if running 24/7) - **stop when not in use!**
- **EBS Storage (90GB)**: ~$7/month
- **AWS Config**: ~$2/month per recorder + $0.003 per config item
- **S3 Storage**: ~$0.023/GB/month (Standard tier)
- **S3 Requests**: Minimal (Config writes)
- **Data Transfer**: Free within same region

**Cost-Saving Tips**:
- **Stop EC2 instances** when not actively testing (biggest savings!)
- Config data moved to STANDARD_IA after 90 days (~50% cheaper)
- Old Config data moved to Glacier after 365 days (~80% cheaper)
- No KMS charges (using AWS-managed keys)
- Use SSM Session Manager instead of SSH to avoid NAT gateway costs

**Estimated Monthly Cost**:
- With EC2 running: ~$75/month
- With EC2 stopped: ~$15/month (S3 + Config + EBS storage only)

## License

MIT

## Author

Johnny Endrihs
- GitHub: [hmbldv](https://github.com/hmbldv)
- GitLab: Private GitLab for CI/CD deployment

---

**Built as part of DevSecOps portfolio** demonstrating:
- Infrastructure as Code (Terraform)
- AWS Security Best Practices
- AWS Config for Compliance Monitoring
- CI/CD Automation (GitLab)
- OIDC Federation
- Cost Optimization
- Security Testing Lab Environments

*Preparing for AWS Certified Security - Specialty*
