output "instance_info" {
  value = {
    id       = vultr_instance.taps.id
    hostname = vultr_instance.taps.hostname
    region   = vultr_instance.taps.region
    plan     = vultr_instance.taps.plan
    status   = vultr_instance.taps.status
  }
}

output "network_info" {
  description = "Network information from Vultr API"
  value = {
    main_ip    = vultr_instance.taps.main_ip
    gateway_v4 = vultr_instance.taps.gateway_v4
    netmask_v4 = vultr_instance.taps.netmask_v4
  }
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh root@${vultr_instance.taps.main_ip}"
}

output "clan_commands" {
  description = "Clan commands for provisioning"
  value = {
    install = "clan machines install taps --target-host root@${vultr_instance.taps.main_ip}"
  }
}

output "console_url" {
  description = "Vultr console (click 'View Console' for VNC)"
  value       = "https://my.vultr.com/subs/?id=${vultr_instance.taps.id}"
}
