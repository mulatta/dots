data "github_repositories" "all-repos" {
  query = "user:mulatta is:public"
}

data "github_repositories" "non-archived-repos" {
  query = "user:mulatta is:public archived:false"
}

resource "gitlab_project" "repos" {
  for_each                            = toset(data.github_repositories.all-repos.full_names)
  name                                = element(split("/", each.key), 1)
  import_url                          = "https://github.com/${each.key}"
  mirror                              = true
  mirror_trigger_builds               = true
  mirror_overwrites_diverged_branches = true
  shared_runners_enabled              = false
  visibility_level                    = "public"
}

resource "github_repository_webhook" "gitlab" {
  for_each   = toset(data.github_repositories.non-archived-repos.names)
  repository = each.key

  configuration {
    url          = "https://gitlab.com/api/v4/projects/mulatta%2F${each.key}/mirror/pull?private_token=${data.sops_file.secrets.data["GITLAB_TOKEN"]}"
    content_type = "form"
  }

  active = true

  events = ["push", "pull_request"]
}
