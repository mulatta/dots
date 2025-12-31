resource "vultr_firewall_group" "taps" {
  description = "Firewall rules for taps"
}

resource "vultr_firewall_rule" "ssh" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "22"
  notes             = "SSH access"
}

resource "vultr_firewall_rule" "http" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "80"
  notes             = "HTTP access"
}

resource "vultr_firewall_rule" "https" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "443"
  notes             = "HTTPS access"
}

resource "vultr_firewall_rule" "wireguard_mgnt" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "51820"
  notes             = "WireGuard management interface"
}

resource "vultr_firewall_rule" "wireguard_serv" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "51821"
  notes             = "WireGuard service interface"
}

resource "vultr_firewall_rule" "zerotier" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "9993"
  notes             = "ZeroTier VPN"
}

output "firewall_info" {
  description = "Firewall configuration dtapsils"
  value = {
    firewall_group_id   = vultr_firewall_group.taps.id
    description         = vultr_firewall_group.taps.description
    applied_to_instance = vultr_instance.taps.id
  }
}
