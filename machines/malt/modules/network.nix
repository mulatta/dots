{
  networking = {
    useDHCP = false;

    interfaces.enp1s0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.80.169.67";
          prefixLength = 24;
        }
      ];
    };

    defaultGateway = {
      address = "10.80.169.254";
      interface = "enp1s0";
    };

    nameservers = [
      "117.16.191.6"
      "168.126.63.1"
    ];
  };
}
