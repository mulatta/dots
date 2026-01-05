{ config, ... }:
let
  domain = "ca.x";
in
{
  security.acme.certs.${domain}.server = "https://${domain}:1443/acme/acme/directory";

  services.nginx.virtualHosts.${domain} = {
    addSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "https://localhost:1443";
    };
    locations."= /ca.crt".alias =
      config.clan.core.vars.generators.step-intermediate-cert.files."intermediate.crt".path;
  };
}
