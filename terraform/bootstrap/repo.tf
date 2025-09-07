terraform {
  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    gitlab = { source = "gitlabhq/gitlab" }
    sops   = { source = "carlpett/sops" }
  }
}

provider "gitlab" {
  token = data.sops_file.secrets.data["GITLAB_TOKEN"]
}

resource "gitlab_project" "dots" {
  name             = "dots"
  description      = "My personal dotfiles"
  visibility_level = "public"
}

output "project_id" {
  value       = gitlab_project.dots.id
  description = "GitLab project ID for terraform state storage"
}
