variable "plan" {
  description = "Vultr plan ID for the instance"
  type        = string
  default     = "vc2-2c-4gb"

  validation {
    condition     = can(regex("^vc2-", var.plan))
    error_message = "Plan must be a valid Vultr plan ID starting with 'vc2-'."
  }
}

variable "hostname" {
  description = "NixOS hostname"
  type        = string
  default     = "nixos-vultr"
}

variable "os" {
  description = "Operating system name"
  type        = string
  default     = "Ubuntu 22.04 LTS x64"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

