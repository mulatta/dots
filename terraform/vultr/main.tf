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

data "vultr_os" "selected" {
  filter {
    name   = "name"
    values = [var.os]
  }
}

resource "vultr_ssh_key" "eta" {
  name    = "${var.hostname}-ssh-key"
  ssh_key = file(var.ssh_public_key_path)
}

# Main instance resource
resource "vultr_instance" "eta" {
  hostname = var.hostname
  region   = data.vultr_region.selected.id
  plan     = data.vultr_plan.selected.id
  os_id    = data.vultr_os.selected.id

  ssh_key_ids = [vultr_ssh_key.eta.id]

  enable_ipv6 = false
  backups     = "disabled"

  # Security configuration
  firewall_group_id = vultr_firewall_group.eta.id

  # lifecycle {
  #   ignore_changes = [
  #     os_id
  #   ]
  # }
}

resource "null_resource" "get_network_info_from_remote" {
  depends_on = [vultr_instance.eta]

  connection {
    type        = "ssh"
    user        = "root"
    host        = vultr_instance.eta.main_ip
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "local-exec" {
    command = <<EOT
      ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
          -i ${var.ssh_private_key_path} root@${vultr_instance.eta.main_ip} \
          'IPV4=$(hostname -I | awk "{print \$1}") && \
           MAC=$(ip link show enp1s0 | awk "/ether/ {print \$2}") && \
           GATEWAY=$(ip route | awk "/default/ {print \$3}") && \
           DNS=$(awk "/^nameserver/ {print \$2}" /etc/resolv.conf | head -n1) && \
           jq -n --arg ipv4 "$IPV4" \
                 --arg mac "$MAC" \
                 --arg gateway "$GATEWAY" \
                 --arg dns "$DNS" \
                 "{ipv4: \$ipv4, mac: \$mac, gateway: \$gateway, dns: \$dns}"' \
      > netinfo.json
    EOT
  }
}

data "local_file" "network_info" {
  depends_on = [null_resource.get_network_info_from_remote]
  filename   = "${path.module}/netinfo.json"
}
