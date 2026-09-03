{
  services.nginx.virtualHosts."radicle-mirror.mulatta.io" = {
    forceSSL = true;
    enableACME = true;

    # radicle-mirror validates GitHub's signature before accepting payloads.
    # Expose only webhook endpoint; service has no public administrative UI.
    locations."= /github" = {
      proxyPass = "http://127.0.0.1:4128";
      recommendedProxySettings = true;
    };
    locations."/".return = "404";
  };
}
