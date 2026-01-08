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

# Rewrite / to /index.html for R2 custom domain
resource "cloudflare_ruleset" "cache_index_rewrite" {
  zone_id = local.zone_id
  name    = "Cache index.html rewrite"
  kind    = "zone"
  phase   = "http_request_transform"

  rules = [{
    action = "rewrite"
    action_parameters = {
      uri = {
        path = {
          value = "/index.html"
        }
      }
    }
    expression  = "(http.host eq \"cache.mulatta.io\" and http.request.uri.path eq \"/\")"
    description = "Serve index.html at root for cache.mulatta.io"
    enabled     = true
  }]
}
