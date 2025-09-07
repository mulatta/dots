provider "gitlab" {
  token = data.sops_file.secrets.data["GITLAB_TOKEN"]
}
