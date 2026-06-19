{
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "zotero.mulatta.io";
  kanidmDomain = "idm.mulatta.io";
  # zhost's internal listen address (kept off the public interface; nginx fronts it).
  zhostUpstream = "http://127.0.0.1:8189";

  # A dedicated oauth2-proxy instance fronts ONLY zhost's /login path (see
  # nginx/zotero.nix). zhost is public for sync; enrollment is the one action
  # that must be tied to an identity, so the proxy authenticates the browser
  # against kanidm and forwards X-Auth-Request-Email, which zhost matches against
  # loginAuthorizedUser. Mirrors the restate proxy in oauth2-proxy.nix; the
  # upstream is local because zhost runs on taps.
  zhostOauth2Args = [
    "--provider=oidc"
    "--client-id=zhost"
    "--oidc-issuer-url=https://${kanidmDomain}/oauth2/openid/zhost"
    "--redirect-url=https://${domain}/oauth2/callback"
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
    "--cookie-domain=${domain}"
    "--cookie-name=_oauth2_proxy_zhost"
    "--cookie-secure=true"
    "--cookie-httponly=true"
    "--cookie-refresh=1h"
    "--cookie-expire=72h"
    "--upstream=${zhostUpstream}"
    "--http-address=127.0.0.1:4182"
  ];
in
{
  imports = [ self.inputs.zhost.nixosModules.zhost ];

  # zhost's nixosModule defaults services.zhost.package to pkgs.zhost, provided
  # by the flake's overlay (which also re-points zotero and adds rustfs; both
  # harmless on a server).
  nixpkgs.overlays = [ self.inputs.zhost.overlays.default ];

  # Secrets: the API key is minted here (openssl); the R2 credentials are an
  # external capability (a bucket-scoped R2 API token created in the Cloudflare
  # dashboard) supplied once at deploy via hidden prompts and persisted.
  clan.core.vars.generators.zhost = {
    files.api-key = {
      secret = true;
      owner = config.services.zhost.user;
    };
    files.r2-access-key = {
      secret = true;
      owner = config.services.zhost.user;
    };
    files.r2-secret-key = {
      secret = true;
      owner = config.services.zhost.user;
    };

    prompts.r2-access-key = {
      description = "zhost R2 Access Key ID (zotero bucket)";
      type = "hidden";
      persist = true;
    };
    prompts.r2-secret-key = {
      description = "zhost R2 Secret Access Key (zotero bucket)";
      type = "hidden";
      persist = true;
    };

    runtimeInputs = with pkgs; [
      coreutils
      openssl
    ];

    script = ''
      openssl rand -hex 32 > "$out/api-key"
      cat "$prompts/r2-access-key" > "$out/r2-access-key"
      cat "$prompts/r2-secret-key" > "$out/r2-secret-key"
    '';
  };

  # Cookie-signing key for the zhost oauth2-proxy; the OIDC client is public
  # (PKCE), so the client secret is an unused placeholder. Same shape as the
  # generators in oauth2-proxy.nix.
  clan.core.vars.generators.oauth2-proxy-zhost = {
    files.env = {
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

  services.zhost = {
    enable = true;
    bind = "127.0.0.1:8189";
    publicUrl = "https://${domain}";
    # Local PostgreSQL over the peer socket; createLocalDatabase (default true)
    # provisions the zhost database and role on taps's postgres.
    loginAuthorizedUser = "seungwon@mulatta.io";

    apiKeyFile = config.clan.core.vars.generators.zhost.files.api-key.path;

    s3 = {
      endpoint = "https://a36871be6860124304dfb5c3b3eb8c1a.r2.cloudflarestorage.com";
      region = "auto";
      bucket = "zotero";
      pathStyle = true;
      presignTtl = 300;
      accessKeyFile = config.clan.core.vars.generators.zhost.files.r2-access-key.path;
      secretKeyFile = config.clan.core.vars.generators.zhost.files.r2-secret-key.path;
    };
  };

  systemd.services.oauth2-proxy-zhost = {
    description = "OAuth2 Proxy for zhost enrollment (/login)";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "kanidm.service"
      "network-online.target"
    ];
    after = [
      "kanidm.service"
      "network-online.target"
    ];
    restartTriggers = [ config.clan.core.vars.generators.oauth2-proxy-zhost.files.env.path ];
    serviceConfig = {
      User = "oauth2-proxy";
      Group = "oauth2-proxy";
      EnvironmentFile = config.clan.core.vars.generators.oauth2-proxy-zhost.files.env.path;
      ExecStart = "${lib.getExe config.services.oauth2-proxy.package} ${lib.escapeShellArgs zhostOauth2Args}";
      Restart = "always";
    };
  };
}
