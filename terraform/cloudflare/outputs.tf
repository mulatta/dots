output "r2_cache_bucket" {
  value = cloudflare_r2_bucket.cache.name
}

output "account_id" {
  value     = local.account_id
  sensitive = true
}

output "r2_buzz_bucket" {
  value = cloudflare_r2_bucket.buzz.name
}
