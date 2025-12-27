provider "cloudflare" {
  api_token = data.sops_file.secrets.data["CLOUDFLARE_API_TOKEN"]
}

data "cloudflare_accounts" "main" {}

locals {
  account_id = data.cloudflare_accounts.main.result[0].id
}
