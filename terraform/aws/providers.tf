provider "aws" {
  region     = var.aws_region
  access_key = data.sops_file.secrets.data["AWS_ACCESS_KEY_ID"]
  secret_key = data.sops_file.secrets.data["AWS_SECRET_ACCESS_KEY"]
}

provider "cloudflare" {
  api_token = data.sops_file.secrets.data["CLOUDFLARE_API_TOKEN"]
}

variable "aws_region" {
  description = "AWS region for SES"
  type        = string
  default     = "us-east-1"
}
