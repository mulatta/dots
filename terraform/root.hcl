locals {
  secrets       = yamldecode(sops_decrypt_file("${get_parent_terragrunt_dir()}/secrets.yaml"))
  r2_account_id = local.secrets.CLOUDFLARE_ACCOUNT_ID
}

# Provider versions and builds come from flake.lock via opentofu.withPlugins.
# Run inside the terraform devshell. Clean the *execution directory*, not only
# the source directory: Terragrunt may reuse a cached lock after source changes.
# Auto-init is disabled in the shell: initialize explicitly before plan/apply.
terraform {
  before_hook "check_nix_provider_environment" {
    commands = ["init", "plan", "apply", "validate", "destroy", "import", "refresh", "providers", "state", "output", "show"]
    execute  = [get_env("DOTS_TERRAFORM_GUARD", "/missing-terraform-devshell")]
  }

  before_hook "reset_nix_provider_metadata" {
    commands = ["init"]
    execute = ["bash", "-eu", "-c", <<-EOT
      # Repeat the guard here so metadata deletion never depends on hook order.
      "$${DOTS_TERRAFORM_GUARD:?Use the Terraform devshell}"
      rm -f .terraform.lock.hcl
      rm -rf -- "$${TF_DATA_DIR:-.terraform}/providers"
    EOT
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
