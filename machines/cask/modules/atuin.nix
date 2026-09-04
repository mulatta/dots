{
  services.atuin = {
    enable = true;
    openRegistration = false;
  };
  services.nginx.virtualHosts."atuin.mulatta.io" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:8888";
  };
}
