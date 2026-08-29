# Re-enable with taps provisioning under issue #424.
/*
output "taps" {
  description = "Taps standby instance and provider-reported network information"
  value = {
    instance = {
      id       = vultr_instance.taps.id
      hostname = vultr_instance.taps.hostname
      region   = vultr_instance.taps.region
      plan     = vultr_instance.taps.plan
      status   = vultr_instance.taps.status
    }
    network = {
      main_ipv4 = vultr_instance.taps.main_ip
      gateway   = vultr_instance.taps.gateway_v4
      netmask   = vultr_instance.taps.netmask_v4
    }
    firewall = {
      id          = vultr_firewall_group.taps_standby.id
      description = vultr_firewall_group.taps_standby.description
    }
    console_url = "https://my.vultr.com/subs/?id=${vultr_instance.taps.id}"
  }
}
*/

output "cask" {
  description = "Cask production instance and network information"
  value = {
    instance = {
      id       = vultr_instance.cask.id
      hostname = vultr_instance.cask.hostname
      region   = vultr_instance.cask.region
      plan     = vultr_instance.cask.plan
      status   = vultr_instance.cask.status
    }
    network = {
      main_ipv4     = vultr_instance.cask.main_ip
      reserved_ipv4 = vultr_reserved_ip.service.subnet
      gateway       = vultr_instance.cask.gateway_v4
      netmask       = vultr_instance.cask.netmask_v4
      ipv6          = vultr_instance.cask.v6_main_ip
      ipv6_network  = vultr_instance.cask.v6_network
      ipv6_size     = vultr_instance.cask.v6_network_size
    }
    firewall = {
      id          = vultr_firewall_group.cask.id
      description = vultr_firewall_group.cask.description
    }
    console_url = "https://my.vultr.com/subs/?id=${vultr_instance.cask.id}"
  }
}

output "service_ipv4" {
  description = "Reserved IPv4 consumed by production DNS records"
  value       = vultr_reserved_ip.service.subnet
}

output "service_ipv6" {
  description = "Stable IPv6 consumed by authoritative DNS records"
  value       = vultr_instance.cask.v6_main_ip
}

output "ptr_record" {
  description = "PTR record for the production mail endpoint"
  value = {
    ip      = vultr_reverse_ipv4.mail.ip
    reverse = vultr_reverse_ipv4.mail.reverse
  }
}
