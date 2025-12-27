provider "vultr" {
  api_key     = data.sops_file.secrets.data["VULTR_API"]
  rate_limit  = 700
  retry_limit = 3
}
