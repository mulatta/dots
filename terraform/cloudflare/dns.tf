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

output "mail_dns" {
  value = {
    mail_server = local.mail_domain
    ip          = local.taps_ip
  }
}
