# dots - dotfiles, NixOS configs
resource "github_repository" "dots" {
  name                   = "dots"
  description            = "My personal dotfiles"
  visibility             = "public"
  allow_auto_merge       = true
  delete_branch_on_merge = true
  topics                 = ["build-with-buildbot"]

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

  required_status_checks {
    strict   = false
    contexts = ["buildbot/nix-eval"]
  }
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

resource "github_issue_label" "auto_merge" {
  repository  = github_repository.dots.name
  name        = "auto-merge"
  description = "Auto-merge this PR"
  color       = "7D7C02"
}

# toolz - bioinformatics Nix packages
resource "github_repository" "toolz" {
  name                   = "toolz"
  description            = "Bioinformatics tools for Nix"
  visibility             = "public"
  allow_auto_merge       = true
  delete_branch_on_merge = true
  topics                 = ["nix", "bioinformatics", "build-with-buildbot"]

  pages {
    build_type = "workflow"
  }

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }
}

resource "github_branch_protection" "toolz_main" {
  repository_id = github_repository.toolz.node_id
  pattern       = "main"

  allows_force_pushes = false
  allows_deletions    = false

  required_status_checks {
    strict   = false
    contexts = ["buildbot/nix-eval"]
  }
}

