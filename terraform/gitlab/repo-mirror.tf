data "github_repositories" "all-repos" {
  query = "user:mulatta is:public"
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
