{ ... }:
{
  services.radicle = {
    # httpd (web UI)
    httpd = {
      enable = true;
      listenAddress = "127.0.0.1";
      listenPort = 8889;
    };

    settings.node = {
      externalAddresses = [ "64.176.225.253:8776" ];
    };
  };
}
