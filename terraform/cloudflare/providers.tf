provider "cloudflare" {
  api_token = data.sops_file.cloudflare_token.raw
}

data "cloudflare_accounts" "main" {}

locals {
  account_id = data.cloudflare_accounts.main.result[0].id
}
