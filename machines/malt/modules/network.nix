{
  networking = {
    useDHCP = false;
    # Either onboard port may be cabled; only physical NICs get DHCP.
    interfaces.enp1s0.useDHCP = true;
    interfaces.enp2s0.useDHCP = true;
  };
}
