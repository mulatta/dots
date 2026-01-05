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

resource "cloudflare_dns_record" "mta_sts_a" {
  zone_id = local.zone_id
  name    = "mta-sts"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "auth_a" {
  zone_id = local.zone_id
  name    = "auth"
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

resource "cloudflare_dns_record" "nextcloud_a" {
  zone_id = local.zone_id
  name    = "nextcloud"
  content = local.taps_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

output "mail_dns" {
  value = {
    mail_server = local.mail_domain
    ip          = local.taps_ip
  }
}
