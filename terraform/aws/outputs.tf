output "ses_smtp_endpoint" {
  description = "AWS SES SMTP endpoint"
  value       = "email-smtp.${var.aws_region}.amazonaws.com"
}

output "ses_smtp_port" {
  description = "AWS SES SMTP port (STARTTLS)"
  value       = 587
}

output "ses_smtp_username" {
  description = "SMTP username (IAM Access Key ID)"
  value       = aws_iam_access_key.smtp.id
}

output "ses_smtp_password" {
  description = "SMTP password (derived from IAM Secret Access Key)"
  value       = aws_iam_access_key.smtp.ses_smtp_password_v4
  sensitive   = true
}

output "ses_dkim_tokens" {
  description = "SES DKIM tokens for DNS records"
  value       = aws_ses_domain_dkim.main.dkim_tokens
}

output "ses_domain_verification_token" {
  description = "SES domain verification TXT record value"
  value       = aws_ses_domain_identity.main.verification_token
}

output "cloudflare_dkim_records" {
  description = "Created Cloudflare DKIM records"
  value = [
    for record in cloudflare_dns_record.ses_dkim : {
      name    = record.name
      content = record.content
      type    = record.type
    }
  ]
}
