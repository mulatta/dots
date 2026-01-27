data "cloudflare_zones" "mulatta_io" {
  name = "mulatta.io"
}

data "terraform_remote_state" "vultr" {
  backend = "s3"
  config = {
    bucket                      = "dots-tfstate"
    key                         = "vultr/terraform.tfstate"
    region                      = "auto"
    access_key                  = local.r2_access_key_id
    secret_key                  = local.r2_secret_access_key
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
    endpoints = {
      s3 = "https://${local.account_id}.r2.cloudflarestorage.com"
    }
  }
}

locals {
  zone_id     = data.cloudflare_zones.mulatta_io.result[0].id
  taps_ip     = data.terraform_remote_state.vultr.outputs.network_info.main_ip
  mail_domain = "mail.mulatta.io"
  base_domain = "mulatta.io"
}

resource "cloudflare_dns_record" "mail_a" {
  zone_id = local.zone_id
  name    = "mail"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "mta_sts_a" {
  zone_id = local.zone_id
  name    = "mta-sts"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "idm_a" {
  zone_id = local.zone_id
  name    = "idm"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "vaultwarden_a" {
  zone_id = local.zone_id
  name    = "vaultwarden"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "n8n_a" {
  zone_id = local.zone_id
  name    = "n8n"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "n8n_api_a" {
  zone_id = local.zone_id
  name    = "n8n-api"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "cloud_a" {
  zone_id = local.zone_id
  name    = "cloud"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "immich_a" {
  zone_id = local.zone_id
  name    = "immich"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

# cache.mulatta.io - managed by cloudflare_r2_custom_domain in r2.tf

resource "cloudflare_dns_record" "niks3_a" {
  zone_id = local.zone_id
  name    = "niks3"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "atuin_a" {
  zone_id = local.zone_id
  name    = "atuin"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "rad_a" {
  zone_id = local.zone_id
  name    = "rad"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "links_a" {
  zone_id = local.zone_id
  name    = "links"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

# =============================================================================
# Mail DNS Records (migrated from cloudflare-dns.nix)
# =============================================================================

# MX record
resource "cloudflare_dns_record" "mx" {
  zone_id  = local.zone_id
  name     = "@"
  content  = local.mail_domain
  type     = "MX"
  priority = 10
  ttl      = 300
}

# SPF record - allows mail server and Resend (via AWS SES)
resource "cloudflare_dns_record" "spf" {
  zone_id = local.zone_id
  name    = "@"
  content = "v=spf1 include:amazonses.com mx ~all"
  type    = "TXT"
  ttl     = 300
}

# DMARC record
resource "cloudflare_dns_record" "dmarc" {
  zone_id = local.zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=quarantine; rua=mailto:dmarc@${local.base_domain}"
  type    = "TXT"
  ttl     = 300
}

# =============================================================================
# Resend DNS Records (outbound relay)
# =============================================================================

# Resend DKIM
resource "cloudflare_dns_record" "resend_dkim" {
  zone_id = local.zone_id
  name    = "resend._domainkey"
  type    = "TXT"
  content = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDZhMdIzvq/fPFBHZ+Cn7uJij3gNXbBKulXcMm6n2OhA3iGuNJbjAAqDUiB5TxktsOrGNLE66sszpSZsC/JBbtLnMuMpHDnf6QwomDnj1ngwQnivJB6CF5vphgHWb2qRKkbNTNKITwuEWR6LPePATHJ3oFzxQIU3gGeu4261HqpHwIDAQAB"
  ttl     = 300
  comment = "Resend DKIM verification"
}

# Resend return-path MX (for bounce handling)
resource "cloudflare_dns_record" "resend_send_mx" {
  zone_id  = local.zone_id
  name     = "send"
  type     = "MX"
  content  = "feedback-smtp.ap-northeast-1.amazonses.com"
  priority = 10
  ttl      = 300
  comment  = "Resend bounce handling"
}

# Resend return-path SPF
resource "cloudflare_dns_record" "resend_send_spf" {
  zone_id = local.zone_id
  name    = "send"
  type    = "TXT"
  content = "v=spf1 include:amazonses.com ~all"
  ttl     = 300
  comment = "Resend SPF for return-path"
}

# MTA-STS record
resource "cloudflare_dns_record" "mta_sts_txt" {
  zone_id = local.zone_id
  name    = "_mta-sts"
  content = "v=STSv1; id=20250106"
  type    = "TXT"
  ttl     = 300
}

# TLS-RPT record
resource "cloudflare_dns_record" "tlsrpt" {
  zone_id = local.zone_id
  name    = "_smtp._tls"
  content = "v=TLSRPTv1; rua=mailto:tls-reports@${local.base_domain}"
  type    = "TXT"
  ttl     = 300
}

# Autodiscover (Outlook)
resource "cloudflare_dns_record" "autodiscover" {
  zone_id = local.zone_id
  name    = "autodiscover"
  content = local.mail_domain
  type    = "CNAME"
  ttl     = 300
  proxied = false
}

# Autoconfig (Thunderbird)
resource "cloudflare_dns_record" "autoconfig" {
  zone_id = local.zone_id
  name    = "autoconfig"
  content = local.mail_domain
  type    = "CNAME"
  ttl     = 300
  proxied = false
}

# CalDAV SRV record
resource "cloudflare_dns_record" "caldav_srv" {
  zone_id = local.zone_id
  name    = "_caldavs._tcp"
  type    = "SRV"
  ttl     = 300
  data = {
    priority = 0
    weight   = 1
    port     = 443
    target   = local.mail_domain
  }
  lifecycle {
    ignore_changes = [priority]
  }
}

# CardDAV SRV record
resource "cloudflare_dns_record" "carddav_srv" {
  zone_id = local.zone_id
  name    = "_carddavs._tcp"
  type    = "SRV"
  ttl     = 300
  data = {
    priority = 0
    weight   = 1
    port     = 443
    target   = local.mail_domain
  }
  lifecycle {
    ignore_changes = [priority]
  }
}

output "mail_dns" {
  value = {
    mail_server = local.mail_domain
    ip          = local.taps_ip
  }
}
