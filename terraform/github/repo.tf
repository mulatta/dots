resource "github_repository" "dots" {
  name             = "dots"
  description      = "My personal dotfiles"
  visibility       = "public"
  allow_auto_merge = true
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
