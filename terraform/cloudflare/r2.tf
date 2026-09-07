# cache - private storage served through niks3 presigned reads

resource "cloudflare_r2_bucket" "cache" {
  account_id = local.account_id
  name       = "cache"
  location   = "APAC"
}

resource "cloudflare_r2_bucket_lifecycle" "cache" {
  account_id  = local.account_id
  bucket_name = cloudflare_r2_bucket.cache.name
  rules = [{
    id      = "abort-incomplete-multipart-uploads"
    enabled = true
    conditions = {
      prefix = ""
    }
    abort_multipart_uploads_transition = {
      condition = {
        max_age = 86400 # 1 day in seconds
        type    = "Age"
      }
    }
  }]
}

# backup

resource "cloudflare_r2_bucket" "backup" {
  account_id = local.account_id
  name       = "backup"
  location   = "APAC"
}

resource "cloudflare_r2_bucket_lifecycle" "backup" {
  account_id  = local.account_id
  bucket_name = cloudflare_r2_bucket.backup.name
  rules = [{
    id      = "abort-incomplete-multipart-uploads"
    enabled = true
    conditions = {
      prefix = ""
    }
    abort_multipart_uploads_transition = {
      condition = {
        max_age = 86400 # 1 day in seconds
        type    = "Age"
      }
    }
  }]
}

# zotero - zhost attachment storage (private; served via zhost presigned URLs)

resource "cloudflare_r2_bucket" "zotero" {
  account_id = local.account_id
  name       = "zotero"
  location   = "APAC"
}

resource "cloudflare_r2_bucket_lifecycle" "zotero" {
  account_id  = local.account_id
  bucket_name = cloudflare_r2_bucket.zotero.name
  rules = [{
    id      = "abort-incomplete-multipart-uploads"
    enabled = true
    conditions = {
      prefix = ""
    }
    abort_multipart_uploads_transition = {
      condition = {
        max_age = 86400 # 1 day in seconds
        type    = "Age"
      }
    }
  }]
}
