locals {
  domain = "mulatta.io"
}

# SES Domain Identity
resource "aws_ses_domain_identity" "main" {
  domain = local.domain
}

# SES Domain DKIM
resource "aws_ses_domain_dkim" "main" {
  domain = aws_ses_domain_identity.main.domain
}

# Zone ID for mulatta.io (looked up via Cloudflare API)
locals {
  zone_id = "d8e6c8821485146f7d1444860b0b0b1f"
}

resource "cloudflare_dns_record" "ses_dkim" {
  count = 3

  zone_id = local.zone_id
  name    = "${aws_ses_domain_dkim.main.dkim_tokens[count.index]}._domainkey"
  type    = "CNAME"
  content = "${aws_ses_domain_dkim.main.dkim_tokens[count.index]}.dkim.amazonses.com"
  ttl     = 300
  proxied = false

  comment = "AWS SES DKIM verification"
}

# SES Domain Identity Verification (optional TXT record)
resource "cloudflare_dns_record" "ses_verification" {
  zone_id = local.zone_id
  name    = "_amazonses"
  type    = "TXT"
  content = aws_ses_domain_identity.main.verification_token
  ttl     = 300
  proxied = false

  comment = "AWS SES domain verification"
}

# IAM User for SMTP authentication
resource "aws_iam_user" "smtp" {
  name = "ses-smtp-user-mulatta"
  path = "/ses/"
}

# IAM Policy for SES sending
resource "aws_iam_user_policy" "smtp_send" {
  name = "ses-send-email"
  user = aws_iam_user.smtp.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendRawEmail",
          "ses:SendEmail"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Access Key for SMTP (will be stored in NixOS secrets)
resource "aws_iam_access_key" "smtp" {
  user = aws_iam_user.smtp.name
}
