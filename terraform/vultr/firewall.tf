resource "vultr_firewall_group" "cask" {
  description = "Production firewall rules for cask"
}

# Re-enable with the taps instance after issue #424 gains srvos ZFS support.
/*
resource "vultr_firewall_group" "taps_standby" {
  description = "Standby firewall rules for taps"
}

resource "vultr_firewall_rule" "taps_ssh" {
  firewall_group_id = vultr_firewall_group.taps_standby.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "22"
  notes = "SSH access"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "taps_naru_tcp" {
  firewall_group_id = vultr_firewall_group.taps_standby.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "655"
  notes = "Naru mesh"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "taps_naru_udp" {
  firewall_group_id = vultr_firewall_group.taps_standby.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "655"
  notes = "Naru mesh"
  lifecycle { ignore_changes = [source] }
}
*/

resource "vultr_firewall_rule" "ssh" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "22"
  notes = "SSH access"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "http" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "80"
  notes = "HTTP access"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "https" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "443"
  notes = "HTTPS access"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "dolt" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "3307"
  notes = "Dolt SQL over TLS"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "naru_tcp" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "655"
  notes = "Naru mesh"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "naru_udp" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "655"
  notes = "Naru mesh"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "wireguard_mgnt" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "51820"
  notes = "WireGuard management interface"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "wireguard_serv" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "51821"
  notes = "WireGuard service interface"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "upterm" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "2323"
  notes = "Upterm relay"
  lifecycle { ignore_changes = [source] }
}

# Mail server
resource "vultr_firewall_rule" "smtp" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "25"
  notes = "SMTP"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "smtps" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "465"
  notes = "SMTPS"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "submission" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "587"
  notes = "SMTP submission"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "imap" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "143"
  notes = "IMAP"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "imaps" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "993"
  notes = "IMAPS"
  lifecycle { ignore_changes = [source] }
}

resource "vultr_firewall_rule" "managesieve" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "4190"
  notes = "ManageSieve"
  lifecycle { ignore_changes = [source] }
}

# Radicle P2P
resource "vultr_firewall_rule" "radicle" {
  firewall_group_id = vultr_firewall_group.cask.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0

  port  = "8776"
  notes = "Radicle P2P"
  lifecycle { ignore_changes = [source] }
}
