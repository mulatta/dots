# Keep the personal tailnet separate from the existing .x management mesh.
{ config, pkgs, ... }:
let
  domain = "hs.mulatta.io";
  port = 8089;
  aclPolicy = {
    tagOwners."tag:citra" = [ "seungwon@" ];
    # Only explicitly selected services belong on this network.
    acls = [ ];
  };
in
{
  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    inherit port;
    settings = {
      server_url = "https://${domain}";
      dns = {
        magic_dns = true;
        # MagicDNS must not capture the control server's domain.
        base_domain = "ts.mulatta.io";
        override_local_dns = false;
      };
      oidc = {
        issuer = "https://idm.mulatta.io/oauth2/openid/headscale";
        client_id = "headscale";
        client_secret_path =
          config.clan.core.vars.generators.kanidm-headscale-oidc.files.headscale-secret.path;
        scope = [
          "openid"
          "email"
          "profile"
        ];
        pkce = {
          enabled = true;
          method = "S256";
        };
      };
      # Personal devices must periodically reauthenticate; tagged servers do not.
      node.expiry = "30d";
      logtail.enabled = false;
      policy = {
        mode = "file";
        path = pkgs.writeText "headscale-policy.json" (builtins.toJSON aclPolicy);
      };
    };
  };

  # Keep long-lived Noise streams unbuffered. Public DERP relays only ciphertext.
  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
