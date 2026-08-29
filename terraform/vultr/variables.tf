# Re-enable when reprovisioning taps under issue #424.
/*
variable "taps_plan" {
  description = "Vultr plan ID for the taps standby instance"
  type        = string
  default     = "vc2-2c-4gb"

  validation {
    condition     = can(regex("^(vc2|vhf|vhp)-", var.taps_plan))
    error_message = "Taps plan must be a valid Cloud Compute plan ID."
  }
}

variable "taps_hostname" {
  description = "NixOS hostname for the taps standby instance"
  type        = string
  default     = "taps"
}
*/

variable "cask_plan" {
  description = "Vultr plan ID for the cask production instance"
  type        = string
  default     = "vhp-4c-8gb-intel"

  validation {
    condition     = can(regex("^(vc2|vhf|vhp)-", var.cask_plan))
    error_message = "Cask plan must be a valid Cloud Compute plan ID."
  }
}

variable "cask_hostname" {
  description = "NixOS hostname for the cask production instance"
  type        = string
  default     = "cask"
}

variable "ssh_provisioning_key_path" {
  description = "Path to the private key used only while installing bootstrap images"
  type        = string
  default     = "~/.ssh/id_ed25519"
}
