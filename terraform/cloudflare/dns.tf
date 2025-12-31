# DNS records for mail.mulatta.io

data "cloudflare_zones" "mulatta_io" {
  name = "mulatta.io"
}

data "terraform_remote_state" "vultr" {
  backend = "s3"
  config = {
    bucket = "mulatta-dots-tfstate"
    key    = "vultr/terraform.tfstate"
    region = "ap-northeast-2"
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

resource "cloudflare_dns_record" "mx" {
  zone_id  = local.zone_id
  name     = "@"
  content  = local.mail_domain
  type     = "MX"
  ttl      = 300
  priority = 10
}

resource "cloudflare_dns_record" "spf" {
  zone_id = local.zone_id
  name    = "@"
  content = "v=spf1 mx ~all"
  type    = "TXT"
  ttl     = 300
}

resource "cloudflare_dns_record" "dmarc" {
  zone_id = local.zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=quarantine; rua=mailto:dmarc@${local.base_domain}"
  type    = "TXT"
  ttl     = 300
}

resource "cloudflare_dns_record" "mta_sts_txt" {
  zone_id = local.zone_id
  name    = "_mta-sts"
  content = "v=STSv1; id=20241230"
  type    = "TXT"
  ttl     = 300
}

resource "cloudflare_dns_record" "mta_sts_a" {
  zone_id = local.zone_id
  name    = "mta-sts"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "tlsrpt" {
  zone_id = local.zone_id
  name    = "_smtp._tls"
  content = "v=TLSRPTv1; rua=mailto:tls-reports@${local.base_domain}"
  type    = "TXT"
  ttl     = 300
}

resource "cloudflare_dns_record" "dkim" {
  zone_id = local.zone_id
  name    = "mail._domainkey"
  content = "v=DKIM1; k=rsa; p=REPLACE_WITH_DKIM_PUBLIC_KEY"
  type    = "TXT"
  ttl     = 300
  lifecycle { ignore_changes = [content] }
}

resource "cloudflare_dns_record" "autodiscover" {
  zone_id = local.zone_id
  name    = "autodiscover"
  content = local.mail_domain
  type    = "CNAME"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "autoconfig" {
  zone_id = local.zone_id
  name    = "autoconfig"
  content = local.mail_domain
  type    = "CNAME"
  ttl     = 300
  proxied = false
}

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
}

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
}

output "mail_dns" {
  value = {
    mail_server = local.mail_domain
    ip          = local.taps_ip
  }
}
