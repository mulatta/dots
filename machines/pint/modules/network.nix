{
  networking = {
    useDHCP = false;

    # Raspberry Pi 5 uses end0 for ethernet
    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.80.169.64";
          prefixLength = 24;
        }
      ];
    };

    defaultGateway = {
      address = "10.80.169.254";
      interface = "end0";
    };

    nameservers = [
      "117.16.191.6"
      "168.126.63.1"
    ];
  };
}
