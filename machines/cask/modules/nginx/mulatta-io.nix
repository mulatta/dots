{
  services.nginx.virtualHosts = {
    "mulatta.io" = {
      useACMEHost = "mulatta.io";
      forceSSL = true;
      locations."/".return = "404";
    };
    "www.mulatta.io" = {
      useACMEHost = "mulatta.io";
      forceSSL = true;
      globalRedirect = "mulatta.io";
    };
  };
}
