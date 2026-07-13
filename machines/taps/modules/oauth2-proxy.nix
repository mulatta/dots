{
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  clanLib = self.inputs.clan-core.lib;
  wgPrefix = self.lib.wgPrefix;
  maltSuffix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "malt";
    generator = "wireguard-network-wireguard";
    file = "suffix";
  };
  maltWgIP = "${wgPrefix}:${maltSuffix}";
  kanidmDomain = "idm.mulatta.io";
  n8nDomain = "n8n.mulatta.io";
  restateDomain = "restate.mulatta.io";
  weechatDomain = "chat.mulatta.io";

  restateOauth2Args = [
    "--provider=oidc"
    "--client-id=restate"
    "--oidc-issuer-url=https://${kanidmDomain}/oauth2/openid/restate"
    "--redirect-url=https://${restateDomain}/oauth2/callback"
    "--scope=openid email profile"
    "--email-domain=mulatta.io"
    "--code-challenge-method=S256"
    "--insecure-oidc-allow-unverified-email=true"
    "--set-xauthrequest=true"
    "--pass-access-token=true"
    "--pass-authorization-header=true"
    "--set-authorization-header=true"
    "--reverse-proxy=true"
    "--skip-provider-button=true"
    "--cookie-domain=${restateDomain}"
    "--cookie-name=_oauth2_proxy_restate"
    "--cookie-secure=true"
    "--cookie-httponly=true"
    "--cookie-refresh=1h"
    "--cookie-expire=72h"
    "--upstream=http://[${maltWgIP}]:9070"
    "--http-address=127.0.0.1:4181"
  ];

  weechatOauth2Args = [
    "--provider=oidc"
    "--client-id=weechat"
    "--oidc-issuer-url=https://${kanidmDomain}/oauth2/openid/weechat"
    "--redirect-url=https://${weechatDomain}/oauth2/callback"
    "--scope=openid email profile"
    "--email-domain=mulatta.io"
    "--code-challenge-method=S256"
    "--insecure-oidc-allow-unverified-email=true"
    "--set-xauthrequest=true"
    "--pass-access-token=true"
    "--pass-authorization-header=true"
    "--set-authorization-header=true"
    "--reverse-proxy=true"
    "--skip-provider-button=true"
    "--cookie-domain=${weechatDomain}"
    "--cookie-name=_oauth2_proxy_weechat"
    "--cookie-secure=true"
    "--cookie-httponly=true"
    "--cookie-refresh=1h"
    "--cookie-expire=72h"
    "--upstream=static://202"
    "--http-address=127.0.0.1:4183"
  ];

  # Both proxies are public OIDC clients, so the only generated secret is the
  # cookie-signing key; the client secret is an unused placeholder.
  mkOauth2ProxySecret = {
    files."env" = {
      secret = true;
      owner = "oauth2-proxy";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      COOKIE_SECRET=$(openssl rand -hex 16)
      cat > "$out/env" <<EOF
      OAUTH2_PROXY_COOKIE_SECRET=$COOKIE_SECRET
      OAUTH2_PROXY_CLIENT_SECRET=unused-public-client
      EOF
    '';
  };
in
{
  # oauth2-proxy needs kanidm to be running for OIDC discovery
  systemd.services.oauth2-proxy = {
    after = [ "kanidm.service" ];
    wants = [ "kanidm.service" ];
  };
  clan.core.vars.generators.oauth2-proxy = mkOauth2ProxySecret;
  clan.core.vars.generators.oauth2-proxy-restate = mkOauth2ProxySecret;
  clan.core.vars.generators.oauth2-proxy-weechat = mkOauth2ProxySecret;

  systemd.services.oauth2-proxy-restate = {
    description = "OAuth2 Proxy for Restate";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "kanidm.service"
      "network-online.target"
    ];
    after = [
      "kanidm.service"
      "network-online.target"
    ];
    restartTriggers = [ config.clan.core.vars.generators.oauth2-proxy-restate.files."env".path ];
    serviceConfig = {
      User = "oauth2-proxy";
      Group = "oauth2-proxy";
      EnvironmentFile = config.clan.core.vars.generators.oauth2-proxy-restate.files."env".path;
      ExecStart = "${lib.getExe config.services.oauth2-proxy.package} ${lib.escapeShellArgs restateOauth2Args}";
      Restart = "always";
    };
  };

  systemd.services.oauth2-proxy-weechat = {
    description = "OAuth2 Proxy for WeeChat";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "kanidm.service"
      "network-online.target"
    ];
    after = [
      "kanidm.service"
      "network-online.target"
    ];
    restartTriggers = [ config.clan.core.vars.generators.oauth2-proxy-weechat.files."env".path ];
    serviceConfig = {
      User = "oauth2-proxy";
      Group = "oauth2-proxy";
      EnvironmentFile = config.clan.core.vars.generators.oauth2-proxy-weechat.files."env".path;
      ExecStart = "${lib.getExe config.services.oauth2-proxy.package} ${lib.escapeShellArgs weechatOauth2Args}";
      Restart = "always";
    };
  };

  services.oauth2-proxy = {
    enable = true;
    provider = "oidc";
    clientID = "n8n";
    keyFile = config.clan.core.vars.generators.oauth2-proxy.files."env".path;

    cookie = {
      # Pin the cookie to the n8n vhost. A wildcard `.mulatta.io`
      # domain would ship the oauth2-proxy session to every sibling
      # site's JavaScript, so an XSS on any mulatta.io subdomain could
      # hijack the n8n session. n8n.mulatta.io is the only consumer,
      # so there is no need to share.
      domain = "n8n.mulatta.io";
      secure = true;
      httpOnly = true;
      refresh = "1h";
      # Hard cap the session at 72h. cookie.refresh (1h) keeps the
      # user signed in as long as kanidm still considers the token
      # valid, so this mostly caps the blast radius of a stolen
      # cookie — 3 days vs 30 days — without hurting everyday UX.
      expire = "72h";
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
      email-domain = "mulatta.io";
      code-challenge-method = "S256";
      insecure-oidc-allow-unverified-email = "true";
    };
  };
}
