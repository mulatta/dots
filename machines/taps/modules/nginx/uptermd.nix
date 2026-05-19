let
  domain = "upterm.mulatta.io";
  port = 2323;
in
{
  services.uptermd = {
    enable = true;
    openFirewall = true;
    inherit port;
    extraFlags = [
      "--hostname"
      domain
    ];
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;
    locations."/".root = ./uptermd;
  };
}
