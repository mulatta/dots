# AWS Access Key

**URL:** https://console.aws.amazon.com/iam/home#/security_credentials

## Steps
1. Access keys section
2. Create new access key (or deactivate old one)
3. Download CSV or copy credentials

## IAM Policy (Terraform + Cost Explorer)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3BucketOperations",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketLocation",
        "s3:GetEncryptionConfiguration",
        "s3:PutEncryptionConfiguration",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetBucketPolicy",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy",
        "s3:GetBucketLogging",
        "s3:PutBucketLogging",
        "s3:GetBucketTagging",
        "s3:PutBucketTagging",
        "s3:PutBucketOwnershipControls",
        "s3:GetBucketOwnershipControls"
      ],
      "Resource": "arn:aws:s3:::mulatta-dots-tfstate"
    },
    {
      "Sid": "S3ObjectOperations",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::mulatta-dots-tfstate/*"
    },
    {
      "Sid": "DynamoDBOperations",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable",
        "dynamodb:CreateTable",
        "dynamodb:DeleteTable",
        "dynamodb:TagResource"
      ],
      "Resource": "arn:aws:dynamodb:ap-northeast-2:*:table/dots-terraform-locks"
    },
    {
      "Sid": "CostExplorerRead",
      "Effect": "Allow",
      "Action": [
        "ce:GetCostAndUsage",
        "ce:GetCostForecast"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSIdentity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

## Update secrets
```bash
sops terraform/secrets.yaml
# Update AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
```

## Verify
```bash
aws sts get-caller-identity
aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-31 --granularity MONTHLY --metrics UnblendedCost
```
