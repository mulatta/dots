resource "github_repository" "dots" {
  name                   = "dots"
  description            = "My personal dotfiles"
  visibility             = "public"
  allow_auto_merge       = true
  delete_branch_on_merge = true

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }
}

resource "github_branch_protection" "main" {
  repository_id = github_repository.dots.node_id
  pattern       = "main"

  allows_force_pushes = false
  allows_deletions    = false
}

resource "github_actions_secret" "app_id" {
  repository      = github_repository.dots.name
  secret_name     = "APP_ID"
  plaintext_value = data.sops_file.secrets.data["GITHUB_APP_ID"]
}

resource "github_actions_secret" "app_private_key" {
  repository      = github_repository.dots.name
  secret_name     = "APP_PRIVATE_KEY"
  plaintext_value = data.sops_file.secrets.data["GITHUB_APP_PRIVATE_KEY"]
}
