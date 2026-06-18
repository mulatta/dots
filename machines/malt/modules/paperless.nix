{
  self,
  config,
  pkgs,
  ...
}:
let
  wgPrefix = self.lib.wgPrefix;
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";

  port = 28981;
  uiDomain = "paperless.mulatta.io";
  apiDomain = "paperless-api.mulatta.io";
  kanidmDomain = "idm.mulatta.io";
in
{
  disko.devices.zpool.zroot.datasets."paperless" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/paperless";
    options."com.sun:auto-snapshot" = "true";
  };

  clan.core.vars.generators.kanidm-paperless-oidc = {
    share = true;
    files.secret.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };

  clan.core.vars.generators.paperless = {
    dependencies = [ "kanidm-paperless-oidc" ];
    files.admin-password = {
      secret = true;
      owner = "paperless";
      group = "paperless";
    };
    files.secret-key = {
      secret = true;
      owner = "paperless";
      group = "paperless";
    };
    files.env = {
      secret = true;
      owner = "paperless";
      group = "paperless";
    };

    runtimeInputs = with pkgs; [
      jq
      openssl
    ];

    script = ''
      openssl rand -base64 32 | tr -d '\n' > "$out/admin-password"
      secret_key=$(openssl rand -base64 64 | tr -d '\n')
      echo -n "$secret_key" > "$out/secret-key"

      oidc_secret=$(cat "$in/kanidm-paperless-oidc/secret")
      providers=$(jq -cn \
        --arg secret "$oidc_secret" \
        --arg server_url "https://${kanidmDomain}/oauth2/openid/paperless" \
        '{openid_connect:{OAUTH_PKCE_ENABLED:true,APPS:[{provider_id:"kanidm",name:"Kanidm",client_id:"paperless",secret:$secret,settings:{server_url:$server_url,oauth_pkce_enabled:true,fetch_userinfo:true,token_auth_method:"client_secret_basic",uid_field:"sub"}}]}}')

      {
        printf 'PAPERLESS_SECRET_KEY=%s\n' "$secret_key"
        printf "PAPERLESS_SOCIALACCOUNT_PROVIDERS='%s'\n" "$providers"
      } > "$out/env"
    '';
  };

  services.paperless = {
    enable = true;
    dataDir = "/var/lib/paperless";
    mediaDir = "/var/lib/paperless/media";
    consumptionDir = "/var/lib/paperless/consume";
    address = maltWgIP;
    inherit port;
    passwordFile = config.clan.core.vars.generators.paperless.files.admin-password.path;
    environmentFile = config.clan.core.vars.generators.paperless.files.env.path;
    database.createLocally = true;

    settings = {
      PAPERLESS_URL = "https://${uiDomain}";
      PAPERLESS_OCR_LANGUAGE = "kor+eng";
      PAPERLESS_TIME_ZONE = "Asia/Seoul";
      PAPERLESS_ALLOWED_HOSTS = "${uiDomain},${apiDomain},[${maltWgIP}]";
      PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://${uiDomain},https://${apiDomain}";
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
      PAPERLESS_DISABLE_REGULAR_LOGIN = true;
      PAPERLESS_REDIRECT_LOGIN_TO_SSO = true;
    };
  };

  systemd.tmpfiles.rules = [
    "Z /var/lib/paperless 0750 paperless paperless -"
    "C+ /var/lib/paperless/nixos-paperless-secret-key 0600 paperless paperless - ${config.clan.core.vars.generators.paperless.files.secret-key.path}"
  ];

  systemd.services.paperless-scheduler = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ port ];
}
