{ pkgs, ... }:
let
  domain = "mulatta.io";
  mailDomain = "mail.${domain}";
in
{
  services.nginx.virtualHosts."mta-sts.${domain}" = {
    enableACME = true;
    forceSSL = true;
    locations."=/.well-known/mta-sts.txt".alias = pkgs.writeText "mta-sts.txt" ''
      version: STSv1
      mode: enforce
      mx: ${mailDomain}
      max_age: 86400
    '';
  };
}
