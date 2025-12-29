{
  # Static IP configuration for malt
  networking = {
    useDHCP = false;

    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.80.169.67";
          prefixLength = 24;
        }
      ];
    };

    defaultGateway = "10.80.169.254";

    nameservers = [
      "117.16.191.6"
      "168.126.63.1"
    ];
  };
}
