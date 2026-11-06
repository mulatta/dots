{
  networking = {
    useDHCP = false;
    # Only the onboard wired port; the Wi-Fi card stays unconfigured.
    interfaces.enp10s0.useDHCP = true;
  };
}
