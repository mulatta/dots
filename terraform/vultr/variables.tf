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
  default     = "taps"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
