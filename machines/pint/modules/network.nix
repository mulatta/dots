{
  networking = {
    useDHCP = false;

    # Raspberry Pi 5 uses end0 for ethernet
    interfaces.end0.useDHCP = true;
  };
}
