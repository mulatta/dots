{
  networking = {
    interfaces.enp1s0 = {
      useDHCP = true;
      ipv4.addresses = [
        {
          address = "64.176.225.253";
          prefixLength = 32;
        }
      ];
    };
    defaultGateway = {
      address = "158.247.204.1";
      interface = "enp1s0";
      source = "64.176.225.253";
      metric = 100;
    };
    firewall.allowedUDPPorts = [ 51820 ];
  };
}
