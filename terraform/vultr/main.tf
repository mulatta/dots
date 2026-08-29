data "vultr_region" "selected" {
  filter {
    name   = "id"
    values = ["icn"]
  }
}

data "vultr_plan" "taps" {
  filter {
    name   = "id"
    values = [var.taps_plan]
  }
}

data "vultr_plan" "cask" {
  filter {
    name   = "id"
    values = [var.cask_plan]
  }
}

resource "vultr_ssh_key" "provisioning" {
  name    = "vultr-provisioning-key"
  ssh_key = chomp(file("${pathexpand(var.ssh_provisioning_key_path)}.pub"))

  lifecycle {
    prevent_destroy = true
  }
}

# Provision with Ubuntu before installing NixOS through Clan.
resource "vultr_instance" "taps" {
  hostname = var.taps_hostname
  label    = var.taps_hostname
  region   = data.vultr_region.selected.id
  plan     = data.vultr_plan.taps.id
  os_id    = 1743 # Ubuntu 22.04 LTS x64 bootstrap image

  ssh_key_ids = [vultr_ssh_key.provisioning.id]

  enable_ipv6 = false
  backups     = "disabled"

  firewall_group_id = vultr_firewall_group.taps_standby.id

  lifecycle {
    prevent_destroy = true
    # Vultr injects this key only while installing the bootstrap image. NixOS
    # owns authorized_keys after provisioning, so key rotation must not reinstall taps.
    ignore_changes = [ssh_key_ids]
  }
}

resource "vultr_instance" "cask" {
  hostname = var.cask_hostname
  label    = var.cask_hostname
  region   = data.vultr_region.selected.id
  plan     = data.vultr_plan.cask.id
  os_id    = 1743 # Ubuntu 22.04 LTS x64 bootstrap image

  ssh_key_ids = [vultr_ssh_key.provisioning.id]

  enable_ipv6 = false
  backups     = "disabled"

  firewall_group_id = vultr_firewall_group.cask.id

  lifecycle {
    prevent_destroy = true
    # Vultr injects this key only while installing the bootstrap image. NixOS
    # owns authorized_keys after provisioning, so key rotation must not reinstall cask.
    ignore_changes = [ssh_key_ids]
  }
}

resource "vultr_reserved_ip" "service" {
  region      = data.vultr_region.selected.id
  ip_type     = "v4"
  label       = "cask-service-ip"
  instance_id = vultr_instance.cask.id

  lifecycle {
    prevent_destroy = true
  }
}

resource "vultr_reverse_ipv4" "mail" {
  instance_id = vultr_instance.cask.id
  ip          = vultr_reserved_ip.service.subnet
  reverse     = "mail.mulatta.io"
}
