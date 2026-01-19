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

# Mail server
resource "vultr_firewall_rule" "smtp" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "25"
  notes             = "SMTP"
}

resource "vultr_firewall_rule" "smtps" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "465"
  notes             = "SMTPS"
}

resource "vultr_firewall_rule" "submission" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "587"
  notes             = "SMTP submission"
}

resource "vultr_firewall_rule" "imap" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "143"
  notes             = "IMAP"
}

resource "vultr_firewall_rule" "imaps" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "993"
  notes             = "IMAPS"
}

resource "vultr_firewall_rule" "managesieve" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "4190"
  notes             = "ManageSieve"
}

# Radicle P2P
resource "vultr_firewall_rule" "radicle" {
  firewall_group_id = vultr_firewall_group.taps.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "8776"
  notes             = "Radicle P2P"
}

output "firewall_info" {
  description = "Firewall configuration"
  value = {
    firewall_group_id   = vultr_firewall_group.taps.id
    description         = vultr_firewall_group.taps.description
    applied_to_instance = vultr_instance.taps.id
  }
}
