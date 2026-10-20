locals {
  secrets       = yamldecode(sops_decrypt_file("${get_parent_terragrunt_dir()}/secrets.yaml"))
  r2_account_id = local.secrets.CLOUDFLARE_ACCOUNT_ID
}

# Keep both lock files and provider links scoped to the Nix package.
download_dir = "${get_original_terragrunt_dir()}/.terragrunt-cache/${get_env("DOTS_TERRAFORM_CACHE_KEY")}"

terraform {
  copy_terraform_lock_file = false
  exclude_from_copy        = [".terraform.lock.hcl", ".terraform", ".terragrunt-cache"]
  before_hook "check_nix_provider_environment" {
    commands = ["init", "plan", "apply", "validate", "destroy", "import", "refresh", "providers", "state", "output", "show"]
    execute  = [get_env("DOTS_TERRAFORM_GUARD", "/missing-terraform-devshell")]
  }

  # Auto-init must not change provider selection while applying a saved plan.
  before_hook "reject_apply_auto_init" {
    commands = ["init"]
    execute = ["bash", "-eu", "-c", <<-EOT
      if [ "$1" = apply ]; then
        echo 'Initialize and create a new reviewed plan in this Nix environment before applying.' >&2
        exit 1
      fi
    EOT
      , "reject-apply-auto-init", get_terraform_command()
    ]
  }
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket = "dots-tfstate"
    key    = "${path_relative_to_include()}/terraform.tfstate"
    region = "auto"

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
generate "secrets" {
  path      = "secrets.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<EOF
data "sops_file" "secrets" {
  source_file = "${get_parent_terragrunt_dir()}/secrets.yaml"
}
EOF
}
