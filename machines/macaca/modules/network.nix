{ ... }:
{
  # macaca is a VPS with public IP
  # WireGuard controller configuration

  config = {
    # WireGuard controller port
    networking.firewall.allowedUDPPorts = [ 51820 ];

    # ZeroTier port (also opened in Vultr firewall)
    # Port 9993/UDP is used by ZeroTier

    # IP forwarding is handled by clan wireguard module
  };
}
