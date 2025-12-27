resource "cloudflare_r2_bucket" "cache" {
  account_id = local.account_id
  name       = "cache"
  location   = "APAC"
}
