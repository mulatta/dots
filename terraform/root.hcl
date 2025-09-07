locals {
  gitlab_project_id = "74242347"
}

remote_state {
  backend = "http"
  config = {
    address        = "https://gitlab.com/api/v4/projects/${local.gitlab_project_id}/terraform/state/${path_relative_to_include()}"
    lock_address   = "https://gitlab.com/api/v4/projects/${local.gitlab_project_id}/terraform/state/${path_relative_to_include()}/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/${local.gitlab_project_id}/terraform/state/${path_relative_to_include()}/lock"
    username       = "mulatta"
    lock_method    = "POST"
    unlock_method  = "DELETE"
  }
}

terraform {
  before_hook "reset old terraform state" {
    commands = ["init"]
    execute  = ["rm", "-f", ".terraform.lock.hcl"]
  }

  extra_arguments "backend_auth" {
    commands = ["init"]
    arguments = [
      "-backend-config=password=${get_env("GITLAB_TOKEN")}"
    ]
  }
}


generate "terraform" {
  path      = "terraform.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    github = { source = "integrations/github" }
    gitlab = { source = "gitlabhq/gitlab" }
    sops   = { source = "carlpett/sops" }
  }

  backend "http" {}
}
EOF
}
