# AWS Config Aggregator Setup Guide

## Overview

This guide explains how to set up an organization-wide AWS Config aggregator in the **sec-tools** account to centralize compliance monitoring across all AWS accounts.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ sec-tools Account (183590991623)                            │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ AWS Config Aggregator                              │    │
│  │ - Collects Config data from all accounts           │    │
│  │ - Provides centralized compliance view             │    │
│  └────────────┬───────────────────────────────────────┘    │
└───────────────┼──────────────────────────────────────────────┘
                │
       ┌────────┴────────┬────────────┬─────────────┐
       │                 │            │             │
       ▼                 ▼            ▼             ▼
┌──────────┐      ┌──────────┐  ┌──────────┐  ┌──────────┐
│ squinks  │      │sec-tools │  │Log Archive│  │Container │
│ (main)   │      │          │  │          │  │Services  │
│          │      │          │  │          │  │          │
│ Config   │      │ Config   │  │ Config   │  │ Config   │
│ Recorder │      │ Recorder │  │ Recorder │  │ Recorder │
└──────────┘      └──────────┘  └──────────┘  └──────────┘
```

## Deployment Steps

### Prerequisites

1. AWS Organizations must be enabled
2. You must have admin access to all accounts
3. AWS Config must be enabled in each source account

### Step 1: Enable AWS Config in Source Accounts

Deploy the Config recorder in each account that you want to aggregate data from:

#### For squinks account (266735821834):
```bash
cd terraform/infrastructure

# Configure for squinks account
export AWS_PROFILE=squinks  # or use appropriate profile

# Initialize and apply
terraform init -backend-config="bucket=terraform-state-266735821834-us-west-1"
terraform apply -target=aws_config_configuration_recorder.main \
                -target=aws_config_delivery_channel.main \
                -target=aws_config_configuration_recorder_status.main
```

#### For other accounts:
Repeat the process for:
- Log Archive (768157413516)
- Container Services (918033868466)
- sec-tools (183590991623) - the aggregator account itself

### Step 2: Deploy Config Aggregator in sec-tools Account

```bash
cd terraform/infrastructure

# Switch to sec-tools account
export AWS_PROFILE=sec-tools  # Use sec-tools profile

# Deploy the aggregator
terraform apply -target=aws_config_configuration_aggregator.organization
```

### Step 3: Verify the Aggregator

```bash
# List aggregators
aws configservice describe-configuration-aggregators

# Check aggregation status
aws configservice describe-configuration-aggregator-sources-status \
    --configuration-aggregator-name organization-aggregator
```

## What This Provides

### Centralized Compliance Monitoring
- View compliance status across all accounts from one location
- Query resource configurations across the organization
- Track configuration changes organization-wide

### Security Posture Management
- Identify misconfigured resources across all accounts
- Monitor security group rules, IAM policies, S3 bucket policies
- Detect drift from security baselines

### Cost Optimization
- Identify unused resources across accounts
- Find over-provisioned instances
- Track resource lifecycle

## Querying the Aggregator

### Example Queries

**Find all S3 buckets without encryption:**
```sql
SELECT
  resourceId,
  accountId,
  awsRegion,
  configuration.serverSideEncryptionConfiguration
WHERE
  resourceType = 'AWS::S3::Bucket'
  AND configuration.serverSideEncryptionConfiguration IS NULL
```

**Find all security groups with 0.0.0.0/0 access:**
```sql
SELECT
  resourceId,
  accountId,
  awsRegion,
  configuration.ipPermissions
WHERE
  resourceType = 'AWS::EC2::SecurityGroup'
  AND configuration.ipPermissions.ipRanges[*].cidrIp = '0.0.0.0/0'
```

**List all IAM users with console access:**
```sql
SELECT
  resourceId,
  accountId,
  configuration.userName,
  configuration.passwordLastUsed
WHERE
  resourceType = 'AWS::IAM::User'
  AND configuration.passwordLastUsed IS NOT NULL
```

## AWS Config Rules (Optional)

After setting up the aggregator, you can create organization-wide Config rules:

```hcl
# Example: Require S3 bucket encryption
resource "aws_config_organization_managed_rule" "s3_encryption" {
  name     = "s3-bucket-server-side-encryption-enabled"
  rule_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"

  depends_on = [aws_config_configuration_aggregator.organization]
}
```

## Cost Considerations

### Per-Account Costs
- **Config Recorder**: ~$2/month per account (recording all resources)
- **Config Rules**: $0.001 per rule evaluation (first 100,000 evaluations free)
- **S3 Storage**: ~$0.023/GB per month

### Example Monthly Cost for 4 Accounts
- Config Recording: 4 × $2 = $8/month
- S3 Storage (assuming 10GB): 10 × $0.023 = $0.23/month
- **Total**: ~$8.23/month

## Troubleshooting

### Aggregator Not Receiving Data
1. Check Config recorder is enabled in source accounts:
   ```bash
   aws configservice describe-configuration-recorders
   aws configservice describe-configuration-recorder-status
   ```

2. Verify IAM role permissions:
   ```bash
   aws iam get-role --role-name AWSConfigAggregatorRole
   ```

3. Check aggregation authorization:
   ```bash
   aws configservice describe-aggregation-authorizations
   ```

### Permission Errors
Ensure the sec-tools account has `organizations:DescribeOrganization` and `organizations:ListAccounts` permissions.

## Security Considerations

1. **S3 Bucket Encryption**: All Config buckets use AES256 encryption
2. **Bucket Policies**: Only Config service can write to buckets
3. **Access Control**: Use IAM policies to restrict who can query the aggregator
4. **Data Retention**: Configure S3 lifecycle policies to manage costs

## Next Steps

1. Set up CloudWatch alarms for compliance violations
2. Create SNS topics for Config rule notifications
3. Integrate with AWS Security Hub for centralized security findings
4. Create custom Config rules for organization-specific requirements

## References

- [AWS Config Aggregator Documentation](https://docs.aws.amazon.com/config/latest/developerguide/aggregate-data.html)
- [AWS Config Rules](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config.html)
- [Advanced Queries](https://docs.aws.amazon.com/config/latest/developerguide/querying-AWS-resources.html)
