provider "cloudflare" {
  api_token = data.sops_file.cloudflare_token.raw
}

data "cloudflare_accounts" "main" {}

data "sops_file" "secrets" {
  source_file = "${path.module}/../secrets.yaml"
}

locals {
  account_id            = data.cloudflare_accounts.main.result[0].id
  cloudflare_account_id = data.sops_file.secrets.data["CLOUDFLARE_ACCOUNT_ID"]
  r2_access_key_id      = data.sops_file.secrets.data["R2_ACCESS_KEY_ID"]
  r2_secret_access_key  = data.sops_file.secrets.data["R2_SECRET_ACCESS_KEY"]
}
