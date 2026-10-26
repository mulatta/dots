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

# Immutable research archive, one top-level folder per finished project.
resource "cloudflare_r2_bucket" "research" {
  account_id = local.account_id
  name       = "research"
  location   = "APAC"
}

locals {
  # Rules only match key prefixes, so each finished project is listed.
  research_raw_prefixes = [
    "Inducible-RNA-Regulator/raw/ngs/",
  ]
}

resource "cloudflare_r2_bucket_lifecycle" "research" {
  account_id  = local.account_id
  bucket_name = cloudflare_r2_bucket.research.name
  rules = concat(
    [{
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
    }],
    # Raw data is rarely read after verification.
    [for prefix in local.research_raw_prefixes : {
      id      = "raw-infrequent-access-${trimsuffix(replace(prefix, "/", "-"), "-")}"
      enabled = true
      conditions = {
        prefix = prefix
      }
      storage_class_transitions = [{
        condition = {
          max_age = 2592000 # 30 days in seconds
          type    = "Age"
        }
        storage_class = "InfrequentAccess"
      }]
    }],
  )
}

# Object tokens cannot delete verified raw data.
resource "cloudflare_r2_bucket_lock" "research" {
  account_id  = local.account_id
  bucket_name = cloudflare_r2_bucket.research.name
  rules = [for prefix in local.research_raw_prefixes : {
    id      = "raw-lock-${trimsuffix(replace(prefix, "/", "-"), "-")}"
    enabled = true
    prefix  = prefix
    condition = {
      type = "Indefinite"
    }
  }]
}
