locals {
  aws_region = get_env("AWS_REGION", "ap-northeast-2")
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "mulatta-dots-tfstate"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = "dots-terraform-locks"
  }
}


generate "terraform" {
  path      = "terraform.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    github     = { source = "integrations/github" }
    gitlab     = { source = "gitlabhq/gitlab" }
    cloudflare = { source = "cloudflare/cloudflare" }
    vultr      = { source = "vultr/vultr" }
    sops       = { source = "carlpett/sops" }
    local      = { source = "hashicorp/local" }
    null       = { source = "hashicorp/null" }
  }
}
EOF
}

generate "secrets" {
  path      = "secrets.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
data "sops_file" "secrets" {
  source_file = "${get_parent_terragrunt_dir()}/secrets.yaml"
}
EOF
}
