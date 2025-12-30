{
  config = {
    networking.firewall.allowedUDPPorts = [ 51820 ];

    # ZeroTier port (also opened in Vultr firewall)
    # Port 9993/UDP is used by ZeroTier
  };
}
