locals {
  secrets       = yamldecode(sops_decrypt_file("${get_parent_terragrunt_dir()}/secrets.yaml"))
  r2_account_id = local.secrets.CLOUDFLARE_ACCOUNT_ID
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "dots-tfstate"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "auto"

    # Cloudflare R2 credentials
    access_key = local.secrets.R2_ACCESS_KEY_ID
    secret_key = local.secrets.R2_SECRET_ACCESS_KEY

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true

    endpoints = {
      s3 = "https://${local.r2_account_id}.r2.cloudflarestorage.com"
    }
  }
}


generate "terraform" {
  path      = "terraform.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    aws        = { source = "hashicorp/aws" }
    github     = { source = "integrations/github" }
    cloudflare = { source = "cloudflare/cloudflare" }
    vultr      = { source = "vultr/vultr" }
    sops       = { source = "carlpett/sops" }
    local      = { source = "hashicorp/local" }
    null       = { source = "hashicorp/null" }
  }
}
EOF
}

# Generate secrets.tf for modules that use the shared secrets.yaml
# Cloudflare module overrides this with its own secrets configuration (clan vars)
generate "secrets" {
  path      = "secrets.tf"
  if_exists = "overwrite_terragrunt"

  # Skip generation for cloudflare module (it has its own secrets.tf)
  disable = strcontains(path_relative_to_include(), "cloudflare")

  contents = <<EOF
data "sops_file" "secrets" {
  source_file = "${get_parent_terragrunt_dir()}/secrets.yaml"
}
EOF
}
