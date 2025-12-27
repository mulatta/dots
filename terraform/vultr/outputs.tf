output "instance_info" {
  value = {
    id       = vultr_instance.macaca.id
    hostname = vultr_instance.macaca.hostname
    region   = vultr_instance.macaca.region
    plan     = vultr_instance.macaca.plan
    status   = vultr_instance.macaca.status
  }
}

output "network_info" {
  description = "Network information from Vultr API"
  value = {
    main_ip    = vultr_instance.macaca.main_ip
    gateway_v4 = vultr_instance.macaca.gateway_v4
    netmask_v4 = vultr_instance.macaca.netmask_v4
  }
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh root@${vultr_instance.macaca.main_ip}"
}

output "clan_commands" {
  description = "Clan commands for provisioning"
  value = {
    install = "clan machines install macaca --target-host root@${vultr_instance.macaca.main_ip}"
  }
}

output "console_url" {
  description = "Vultr console (click 'View Console' for VNC)"
  value       = "https://my.vultr.com/subs/?id=${vultr_instance.macaca.id}"
}
