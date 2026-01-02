{
  pkgs,
  ...
}:
let
  domain = "mail.mulatta.io";
  baseDomain = "mulatta.io";
in
{
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts."_" = {
      default = true;
      rejectSSL = true;
      locations."/".return = "444";
    };

    virtualHosts.${domain} = {
      forceSSL = true;
      enableACME = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:8080";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          client_max_body_size 50M;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };

      locations."= /.well-known/mta-sts.txt".alias = pkgs.writeText "mta-sts.txt" ''
        version: STSv1
        mode: enforce
        mx: ${domain}
        max_age: 86400
      '';
    };

    virtualHosts."mta-sts.${baseDomain}" = {
      forceSSL = true;
      enableACME = true;
      locations."= /.well-known/mta-sts.txt".alias = pkgs.writeText "mta-sts.txt" ''
        version: STSv1
        mode: enforce
        mx: ${domain}
        max_age: 86400
      '';
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@${baseDomain}";
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
