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

# mail-blobs - Stalwart blob store (private; accessed by Stalwart over the S3
# API, never public). Keeping mail bodies/attachments here instead of in
# PostgreSQL keeps the DB and its dumps small.
#
# R2 has no object versioning, so a buggy or malicious delete here is
# unrecoverable on its own. The mail-blobs-backup bucket below holds an
# append-only copy for that purpose (see the rclone copy job in the taps backup
# module). Stalwart's blob garbage collection deletes unreferenced blobs from
# this bucket directly; the backup copy is what survives such deletions.

resource "cloudflare_r2_bucket" "mail_blobs" {
  account_id = local.account_id
  name       = "mail-blobs"
  location   = "APAC"
}

resource "cloudflare_r2_bucket_lifecycle" "mail_blobs" {
  account_id  = local.account_id
  bucket_name = cloudflare_r2_bucket.mail_blobs.name
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

# mail-blobs-backup - append-only copy of mail-blobs. R2 lacks object
# versioning, so this is the recovery path if Stalwart (bug) or a compromised
# token deletes a live blob: a local `rclone copy` (never `sync`) mirrors new
# immutable objects here server-side and never propagates deletions. Stalwart's
# scoped token has no access to this bucket, so a Stalwart compromise cannot
# reach the copy. Grows faster than mail-blobs (it retains deleted blobs too);
# add an age-expiry lifecycle rule here if the recovery window should be bounded.

resource "cloudflare_r2_bucket" "mail_blobs_backup" {
  account_id = local.account_id
  name       = "mail-blobs-backup"
  location   = "APAC"
}

resource "cloudflare_r2_bucket_lifecycle" "mail_blobs_backup" {
  account_id  = local.account_id
  bucket_name = cloudflare_r2_bucket.mail_blobs_backup.name
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
