provider "aws" {
  region                      = "us-east-1"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = "https://s3.mulatta.io"
  }
}

resource "aws_s3_bucket" "neko_transfer" {
  bucket = "neko-transfer"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "neko_transfer" {
  bucket = aws_s3_bucket.neko_transfer.id

  lifecycle {
    ignore_changes = [transition_default_minimum_object_size]
  }

  rule {
    id     = "expire-staging-after-seven-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}
