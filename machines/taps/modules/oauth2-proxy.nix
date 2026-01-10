{
  self,
  config,
  pkgs,
  ...
}:
let
  clanLib = self.inputs.clan-core.lib;
  wgPrefix = config.clan.core.vars.generators.wireguard-network-wireguard.files.prefix.value;
  maltSuffix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "malt";
    generator = "wireguard-network-wireguard";
    file = "suffix";
  };
  maltWgIP = "${wgPrefix}:${maltSuffix}";
  kanidmDomain = "idm.mulatta.io";
  n8nDomain = "n8n.mulatta.io";
in
{
  # oauth2-proxy needs kanidm to be running for OIDC discovery
  systemd.services.oauth2-proxy = {
    after = [ "kanidm.service" ];
    wants = [ "kanidm.service" ];
  };
  clan.core.vars.generators.oauth2-proxy = {
    files."env" = {
      secret = true;
      owner = "oauth2-proxy";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      # Generate exactly 32 hex characters (16 bytes of entropy, 32-byte string)
      COOKIE_SECRET=$(openssl rand -hex 16)
      echo "OAUTH2_PROXY_COOKIE_SECRET=$COOKIE_SECRET" > "$out/env"
    '';
  };

  services.oauth2-proxy = {
    enable = true;
    provider = "oidc";
    clientID = "n8n";
    clientSecret = "unused-public-client";
    keyFile = config.clan.core.vars.generators.oauth2-proxy.files."env".path;

    cookie = {
      domain = ".mulatta.io";
      secure = true;
      httpOnly = true;
    };

    extraConfig = {
      oidc-issuer-url = "https://${kanidmDomain}/oauth2/openid/n8n";
      redirect-url = "https://${n8nDomain}/oauth2/callback";
      scope = "openid email profile";
      set-xauthrequest = "true";
      pass-access-token = "true";
      pass-authorization-header = "true";
      set-authorization-header = "true";
      skip-auth-route = [
        "^/webhook"
        "^/webhook-test"
        "^/healthz"
      ];
      upstream = "http://[${maltWgIP}]:5678";
      http-address = "127.0.0.1:4180";
      cookie-refresh = "1h";
      cookie-expire = "720h"; # 30 days
      email-domain = "mulatta.io";
      code-challenge-method = "S256";
      insecure-oidc-allow-unverified-email = "true";
    };
  };
}
