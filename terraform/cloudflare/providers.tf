provider "cloudflare" {
  api_token = data.sops_file.secrets.data["CLOUDFLARE_API_TOKEN"]
}

locals {
  account_id           = data.sops_file.secrets.data["CLOUDFLARE_ACCOUNT_ID"]
  r2_access_key_id     = data.sops_file.secrets.data["R2_ACCESS_KEY_ID"]
  r2_secret_access_key = data.sops_file.secrets.data["R2_SECRET_ACCESS_KEY"]
}
