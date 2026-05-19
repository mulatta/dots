provider "github" {
  owner = "mulatta"
  token = data.sops_file.secrets.data["GITHUB_TOKEN"]
}
