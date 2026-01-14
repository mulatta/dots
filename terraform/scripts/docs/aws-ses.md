# AWS SES Access Key

IAM user and permission setup guide for AWS SES.

**Note**: These credentials are different from Terraform backend R2 credentials.

- **R2 credentials**: `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` (Cloudflare R2)
- **AWS credentials**: `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (AWS SES, IAM, etc.)

## Create IAM User

**URL:** https://console.aws.amazon.com/iam/home#/users

### Steps

1. Click "Add users"
2. User name: `terraform-ses-admin` (or any preferred name)
3. Select "Attach policies directly"
4. Create and attach the custom IAM Policy below

## IAM Policy (AWS SES)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SESFullAccess",
      "Effect": "Allow",
      "Action": ["ses:*"],
      "Resource": "*"
    },
    {
      "Sid": "IAMUserManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateUser",
        "iam:DeleteUser",
        "iam:GetUser",
        "iam:ListUsers",
        "iam:CreateAccessKey",
        "iam:DeleteAccessKey",
        "iam:ListAccessKeys",
        "iam:PutUserPolicy",
        "iam:DeleteUserPolicy",
        "iam:GetUserPolicy",
        "iam:ListUserPolicies",
        "iam:TagUser",
        "iam:UntagUser",
        "iam:ListUserTags"
      ],
      "Resource": [
        "arn:aws:iam::*:user/ses/*",
        "arn:aws:iam::*:user/ses-smtp-user-*"
      ]
    },
    {
      "Sid": "CloudflareDNSRead",
      "Effect": "Allow",
      "Action": ["route53:GetHostedZone", "route53:ListResourceRecordSets"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    }
  ]
}
```

### Policy Description

| Statement           | Purpose                                                                       |
| ------------------- | ----------------------------------------------------------------------------- |
| `SESFullAccess`     | Manage SES domain identity, DKIM, and sending settings                        |
| `IAMUserManagement` | Allow Terraform to create IAM users for SMTP auth (restricted to ses/\* path) |
| `CloudflareDNSRead` | (Optional) Route53 lookup (Cloudflare is used in practice)                    |

## Create Access Key

1. Go to IAM User detail page → "Security credentials" tab
2. Click "Create access key"
3. Use case: "Third-party service"
4. Download .csv file or copy credentials

## Update secrets.yaml

```bash
# Edit secrets.yaml
sops terraform/secrets.yaml
```

**Add** the following keys (keep existing R2\_\* keys):

```yaml
AWS_ACCESS_KEY_ID: AKIA... # AWS IAM Access Key ID
AWS_SECRET_ACCESS_KEY: xxx... # AWS IAM Secret Access Key
```

**Full structure**:

```yaml
# Cloudflare R2 (Terraform state backend)
R2_ACCESS_KEY_ID: xxx
R2_SECRET_ACCESS_KEY: xxx

# AWS (SES)
AWS_ACCESS_KEY_ID: AKIA...
AWS_SECRET_ACCESS_KEY: xxx

# Cloudflare
CLOUDFLARE_API_TOKEN: xxx
CLOUDFLARE_ACCOUNT_ID: xxx

# Others
GITHUB_TOKEN: xxx
VULTR_API: xxx
```

## Verify Permissions

```bash
# Configure AWS CLI
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="xxx..."
export AWS_DEFAULT_REGION="us-east-1"

# Verify IAM user
aws sts get-caller-identity

# Verify SES permissions
aws ses list-identities --region us-east-1

# Success if no errors (returns empty list initially)
```

## Notes

### Least Privilege Principle

- This IAM user can only manage SES and limited IAM operations
- No permissions for EC2, S3, or other AWS services
- IAM user creation restricted to `/ses/*` path

### Cost Monitoring

SES costs are low, but accidental bulk sending can incur charges:

- Recommended to set up CloudWatch Alarms
- Check sending quota limits (after sandbox removal)

### Access Key Rotation

- Rotate Access Keys every 90 days
- Manage in AWS IAM → Security credentials → Access keys

## Next Steps

After setting up credentials:

1. Run `terraform/aws` module
2. Create SES domain identity
3. DKIM records auto-created (Cloudflare)
4. SMTP credentials generated (Terraform output)
