data "vultr_region" "selected" {
  filter {
    name   = "id"
    values = ["icn"]
  }
}

data "vultr_plan" "selected" {
  filter {
    name   = "id"
    values = [var.plan]
  }
}

resource "vultr_ssh_key" "macaca" {
  name    = "${var.hostname}-ssh-key"
  ssh_key = file(var.ssh_public_key_path)
}

# Main instance resource
# Provision with Ubuntu, then use: clan machines install macaca --target-host root@<IP>
resource "vultr_instance" "macaca" {
  hostname = var.hostname
  region   = data.vultr_region.selected.id
  plan     = data.vultr_plan.selected.id
  os_id    = 1743 # Ubuntu 22.04 LTS x64

  ssh_key_ids = [vultr_ssh_key.macaca.id]

  enable_ipv6 = false
  backups     = "disabled"

  firewall_group_id = vultr_firewall_group.macaca.id
}
