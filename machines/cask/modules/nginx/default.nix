{ config, lib, ... }:
let
  publicDomain = "mulatta.io";
  publicVhostNames = lib.filter (
    name: name == publicDomain || lib.hasSuffix ".${publicDomain}" name
  ) (builtins.attrNames config.services.nginx.virtualHosts);
in
{
  imports = [
    ./home-assistant.nix
    ./jellyfin.nix
    ./linkwarden.nix
    ./miniflux.nix
    ./mulatta-io.nix
    ./nextcloud.nix
    ./paperless.nix
    ./nip05.nix
    ./security-txt.nix
    ./vikunja.nix
  ];

  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.quic = true;
        config.listen = lib.mkDefault [
          {
            addr = "[::1]";
            port = 443;
            ssl = true;
          }
          {
            addr = config.networking.naru.ipv4;
            port = 80;
          }
          {
            addr = config.networking.naru.ipv4;
            port = 443;
            ssl = true;
          }
          {
            addr = "[${config.networking.naru.ipv6}]";
            port = 80;
          }
          {
            addr = "[${config.networking.naru.ipv6}]";
            port = 443;
            ssl = true;
          }
          {
            addr = "[${config.networking.cask.ipv6.address}]";
            port = 80;
          }
          {
            addr = "[${config.networking.cask.ipv6.address}]";
            port = 443;
            ssl = true;
          }
          {
            addr = "0.0.0.0";
            port = 80;
          }
          {
            addr = "0.0.0.0";
            port = 443;
            ssl = true;
          }
        ];
      }
    );
  };

  config = {
    services.nginx = {
      proxyTimeout = "3600s";
      appendHttpConfig = ''
        proxy_headers_hash_max_size 1024;
        proxy_headers_hash_bucket_size 128;

        map $request_uri $block_dotted {
          default 0;
          "~^/\.well-known/" 0;
          "~^/\."            1;
        }
      '';
      commonHttpConfig = ''
        add_header Strict-Transport-Security 'max-age=31536000; includeSubDomains; preload' always;
      '';
      virtualHosts."_" = {
        default = true;
        rejectSSL = true;
        locations."/".return = "444";
      };
    };

    services.logrotate.enable = true;

    networking.firewall = {
      allowedTCPPorts = [
        80
        443
      ];
      allowedUDPPorts = [ 443 ];
    };

    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "acme@mulatta.io";
        server = "https://acme-v02.api.letsencrypt.org/directory";
      };
      certs.${publicDomain} = {
        domain = publicDomain;
        extraDomainNames = lib.sort builtins.lessThan (lib.remove publicDomain publicVhostNames);
        group = "nginx";
        keyType = "ec384";
        webroot = "/var/lib/acme/acme-challenge";
        postRun = "systemctl --no-block reload nginx.service";
      };
    };
  };
}
