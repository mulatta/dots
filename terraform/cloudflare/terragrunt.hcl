include "root" {
  path = find_in_parent_folders("root.hcl")
}

generate "cloudflare_secrets" {
  path      = "secrets.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
data "sops_file" "cloudflare_token" {
  source_file = "$${path.module}/../../vars/per-machine/taps/cloudflare-api/token/secret"
  input_type  = "raw"
}
EOF
}
