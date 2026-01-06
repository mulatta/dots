resource "cloudflare_r2_bucket" "cache" {
  account_id = local.account_id
  name       = "cache"
  location   = "APAC"
}

# Public access via custom domain
# Note: R2 API token (S3 credentials) must be created manually in Dashboard
resource "cloudflare_r2_custom_domain" "cache" {
  account_id  = local.account_id
  bucket_name = cloudflare_r2_bucket.cache.name
  domain      = "cache.mulatta.io"
  zone_id     = local.zone_id
  enabled     = true
}
