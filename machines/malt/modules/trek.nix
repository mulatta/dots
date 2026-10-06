{
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  port = 3010;
  domain = "trek.mulatta.io";
  kanidmDomain = "idm.mulatta.io";
  # Must match the package's stateDir: the server only reaches data/ and
  # uploads/ through symlinks baked into its store path.
  stateDir = "/var/lib/trek";
  trek = self.packages.${pkgs.stdenv.hostPlatform.system}.trek;
in
{
  clan.core.vars.generators.kanidm-trek-oidc = {
    share = true;
    files.secret.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };

  clan.core.vars.generators.trek = {
    dependencies = [ "kanidm-trek-oidc" ];
    files.env.secret = true;
    script = ''
      printf 'OIDC_CLIENT_SECRET=%s\n' "$(cat "$in/kanidm-trek-oidc/secret")" > "$out/env"
    '';
  };

  systemd.services.trek = {
    description = "TREK travel planner";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ stateDir ];

    environment = {
      NODE_ENV = "production";
      HOST = "::";
      PORT = toString port;
      APP_URL = "https://${domain}";
      ALLOWED_ORIGINS = "https://${domain}";
      # cask terminates TLS and forwards over Naru.
      TRUST_PROXY = "1";
      XDG_CACHE_HOME = "%C/trek";

      # Kanidm scope maps gate SSO and admin rights follow the Kanidm admins
      # group. Password login stays on for local accounts the admin creates;
      # cask refuses self-registration.
      OIDC_ISSUER = "https://${kanidmDomain}/oauth2/openid/trek";
      OIDC_CLIENT_ID = "trek";
      OIDC_DISPLAY_NAME = "Kanidm";
      # groups_name yields plain group names instead of SPNs and UUIDs.
      OIDC_SCOPE = "openid email profile groups_name";
      OIDC_ADMIN_CLAIM = "groups";
      OIDC_ADMIN_VALUE = "admins";
    };

    serviceConfig = {
      ExecStart = lib.getExe trek;
      EnvironmentFile = config.clan.core.vars.generators.trek.files.env.path;
      DynamicUser = true;
      StateDirectory = [
        "trek"
        "trek/data"
        "trek/uploads"
      ];
      StateDirectoryMode = "0750";
      CacheDirectory = "trek";
      Restart = "on-failure";

      CapabilityBoundingSet = "";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      UMask = "0027";
    };
  };

  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [ port ];
}
