{
  config,
  pkgs,
  self,
  ...
}:
let
  port = 28981;
  uiDomain = "paperless.mulatta.io";
  apiDomain = "paperless-api.mulatta.io";
  kanidmDomain = "idm.mulatta.io";
in
{
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
    # Outside the Z rule below, whose chmod would mask the Nextcloud ACL.
    consumptionDir = "/srv/files/inbox";
    address = "::";
    inherit port;
    passwordFile = config.clan.core.vars.generators.paperless.files.admin-password.path;
    environmentFile = config.clan.core.vars.generators.paperless.files.env.path;
    database.createLocally = true;
    # Office formats (docx, xlsx, pptx, odt) via Tika + Gotenberg.
    configureTika = true;
    # Every wrapper and service builds PYTHONPATH from passthru.dependencies.
    # overrideAttrs keeps .override, which the module calls.
    package = pkgs.paperless-ngx.overrideAttrs (old: {
      passthru = old.passthru // {
        dependencies = old.passthru.dependencies ++ [
          self.packages.${pkgs.stdenv.hostPlatform.system}.paperless-rhwp
        ];
      };
      # Only the wrapper changes; upstream already tested this source.
      doCheck = false;
    });

    settings = {
      PAPERLESS_URL = "https://${uiDomain}";
      PAPERLESS_OCR_LANGUAGE = "kor+eng";
      # Tesseract otherwise splits Hangul syllables into separate words.
      PAPERLESS_OCR_USER_ARGS = builtins.toJSON {
        tesseract_config = [ "${pkgs.writeText "tesseract-hangul.cfg" "preserve_interword_spaces 1\n"}" ];
      };
      PAPERLESS_TIME_ZONE = "Asia/Seoul";
      PAPERLESS_ALLOWED_HOSTS = "${uiDomain},${apiDomain}";
      PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://${uiDomain},https://${apiDomain}";
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
      PAPERLESS_DISABLE_REGULAR_LOGIN = true;
      PAPERLESS_REDIRECT_LOGIN_TO_SSO = true;
      PAPERLESS_CONSUMER_RECURSIVE = true;
      PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = true;
      # A private/ root lets a later share exclude personal documents; date-first names sort.
      PAPERLESS_FILENAME_FORMAT = "{% if 'private' in tag_name_list %}private/{% endif %}{{ document_type }}/{{ created }} {{ correspondent }} {{ title }}";
    };
  };

  # Linkwarden owns port 3000; Paperless derives its endpoint from this port.
  services.gotenberg.port = 3002;

  systemd.tmpfiles.rules = [
    "Z /var/lib/paperless 0750 paperless paperless -"
    "C+ /var/lib/paperless/nixos-paperless-secret-key 0600 paperless paperless - ${config.clan.core.vars.generators.paperless.files.secret-key.path}"
    "a+ /srv/files/inbox - - - - u:nextcloud:rwx,d:u:nextcloud:rwx,d:u:paperless:rwx"
    "a+ /var/lib/paperless - - - - u:nextcloud:--x"
    "a+ /var/lib/paperless/media - - - - u:nextcloud:--x"
    "a+ /var/lib/paperless/media/documents - - - - u:nextcloud:--x"
    "A+ /var/lib/paperless/media/documents/originals - - - - u:nextcloud:r-X,d:u:nextcloud:r-X"
  ];

  systemd.services.paperless-scheduler = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };

  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [ port ];
}
