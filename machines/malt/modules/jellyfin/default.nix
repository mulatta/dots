{
  self,
  lib,
  config,
  pkgs,
  ...
}:
let
  wgPrefix = self.lib.wgPrefix;
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";
  wgTrustedCidr = "${wgPrefix}::/64";

  port = 8096;
  portString = toString port;
  domain = "video.mulatta.io";
  kanidmDomain = "idm.mulatta.io";
  oidcProvider = "kanidm";
  oidcClientId = "jellyfin";
  oidcEndpoint = "https://${kanidmDomain}/oauth2/openid/${oidcClientId}/";
  oidcAdminGroup = "admins@${kanidmDomain}";
  oidcUserGroup = "media_users@${kanidmDomain}";
  ssoStartUrl = "https://${domain}/sso/OID/start/${oidcProvider}";
  ssoLoginLabel = "Login with Kanidm";

  ssoPlugin = pkgs.jellyfin-plugin-sso-auth;
  ssoVersion = ssoPlugin.version;
  networkConfig = pkgs.replaceVars ./network.xml {
    inherit portString maltWgIP wgTrustedCidr;
  };
  brandingConfig = pkgs.replaceVars ./branding.xml {
    inherit ssoStartUrl ssoLoginLabel;
  };
  ssoConfigTemplate = pkgs.replaceVars ./sso-auth.xml.in {
    inherit
      oidcEndpoint
      oidcClientId
      oidcAdminGroup
      oidcUserGroup
      ;
  };
  replaceSecretsScript =
    {
      file,
      resultPath,
      replacements,
      permissions ? "u=r,g=r,o=",
    }:
    let
      secretName =
        names: "%SECRET${lib.strings.toUpper (lib.concatMapStrings (name: "_" + name) names)}%";
      genReplacement = replacement: {
        name = secretName replacement.name;
        value = "$(cat ${toString replacement.source})";
      };
      checkPermissions = lib.concatMapStringsSep "\n" (
        replacement: "cat ${toString replacement.source} > /dev/null"
      ) replacements;
      sedPatterns = lib.concatMapStringsSep " " (
        replacement: ''-e "s|${replacement.name}|${replacement.value}|"''
      ) (map genReplacement replacements);
      sedCmd = if replacements == [ ] then "cat" else "${pkgs.gnused}/bin/sed ${sedPatterns}";
    in
    ''
      set -euo pipefail

      ${checkPermissions}

      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname ${lib.escapeShellArg resultPath})"
      ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg resultPath}
      ${pkgs.coreutils}/bin/touch ${lib.escapeShellArg resultPath}
      ${sedCmd} ${file} > ${lib.escapeShellArg resultPath}
      ${pkgs.coreutils}/bin/chmod ${permissions} ${lib.escapeShellArg resultPath}
    '';

  mediaArchiveDb = "/srv/media/videos/url-media-archive/A/db";
  mediaArchiveLibrary = "/srv/media/videos/library/A";
  mediaArchiveProjection = pkgs.writeTextFile {
    name = "url-media-archive-projection";
    destination = "/bin/url-media-archive-projection";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      ${builtins.readFile ./url-media-archive-projection.py}
    '';
  };
in
{
  # Declared for NixOS mounts, not for automatic post-provisioning changes.
  # Create these datasets manually on existing malt before switching:
  #   zfs create -o mountpoint=/var/lib/jellyfin -o com.sun:auto-snapshot=true zroot/jellyfin
  #   zfs create -o mountpoint=/srv/media -o com.sun:auto-snapshot=false zroot/media
  disko.devices.zpool.zroot.datasets = {
    "jellyfin" = {
      type = "zfs_fs";
      mountpoint = "/var/lib/jellyfin";
      options."com.sun:auto-snapshot" = "true";
    };
    "media" = {
      type = "zfs_fs";
      mountpoint = "/srv/media";
      options."com.sun:auto-snapshot" = "false";
    };
  };

  clan.core.vars.generators.kanidm-jellyfin-oidc = {
    share = true;
    files.secret = {
      secret = true;
      owner = "jellyfin";
      group = "jellyfin";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };

  services.jellyfin = {
    enable = true;
    openFirewall = false;
    forceEncodingConfig = true;
    hardwareAcceleration = {
      enable = true;
      type = "qsv";
      device = "/dev/dri/renderD128";
    };
    transcoding = {
      enableHardwareEncoding = true;
      enableToneMapping = true;
      hardwareDecodingCodecs = {
        h264 = true;
        hevc = true;
        hevc10bit = true;
        vp9 = true;
        av1 = true;
      };
      hardwareEncodingCodecs = {
        hevc = true;
        av1 = true;
      };
    };
  };

  users.groups.media = { };

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
    "media"
  ];

  systemd.tmpfiles.rules = [
    "d /srv/media 0755 root media -"
    "d /srv/media/movies 0755 jellyfin jellyfin -"
    "d /srv/media/tv 0755 jellyfin jellyfin -"
    "d /srv/media/music 0755 jellyfin jellyfin -"
    "d /srv/media/videos 0755 root media -"
    "d /srv/media/videos/url-media-archive 0755 root media -"
    "d /srv/media/videos/url-media-archive/A 2750 url-media-archive media -"
    "d /srv/media/videos/library 0755 root media -"
    "d /srv/media/videos/library/A 2750 url-media-archive media -"
    "d /var/lib/jellyfin/plugins 0750 jellyfin jellyfin -"
    "d /var/lib/jellyfin/plugins/configurations 0750 jellyfin jellyfin -"
  ];

  systemd.services.url-media-archive-projection = {
    description = "Materialize URL media archive filesystem projection";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "url-media-archive-worker.service"
    ];
    wants = [
      "network-online.target"
      "url-media-archive-worker.service"
    ];
    unitConfig.RequiresMountsFor = [ "/srv/media" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${mediaArchiveProjection}/bin/url-media-archive-projection watch --archive-db ${mediaArchiveDb} --library ${mediaArchiveLibrary} --inotifywait ${pkgs.inotify-tools}/bin/inotifywait";
      User = "url-media-archive";
      Group = "media";
      Restart = "always";
      RestartSec = "5s";
      ReadOnlyPaths = [ mediaArchiveDb ];
      ReadWritePaths = [ mediaArchiveLibrary ];

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
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
    };
  };

  systemd.services.jellyfin = {
    preStart = lib.mkBefore ''
      set -euo pipefail

      plugin_dir=/var/lib/jellyfin/plugins/SSO-Auth_${ssoVersion}
      rm -rf "$plugin_dir"
      cp -R ${ssoPlugin} "$plugin_dir"
      chmod -R u+rwX,go-rwx "$plugin_dir"

      install -m 0600 ${networkConfig} /var/lib/jellyfin/config/network.xml
      install -m 0600 ${brandingConfig} /var/lib/jellyfin/config/branding.xml

      ${replaceSecretsScript {
        file = ssoConfigTemplate;
        resultPath = "/var/lib/jellyfin/plugins/configurations/SSO-Auth.xml";
        replacements = [
          {
            name = [ "OIDC_SECRET" ];
            source = ''"$CREDENTIALS_DIRECTORY/oidc-secret"'';
          }
        ];
      }}
    '';
    serviceConfig.LoadCredential = [
      "oidc-secret:${config.clan.core.vars.generators.kanidm-jellyfin-oidc.files.secret.path}"
    ];
    unitConfig.RequiresMountsFor = [
      "/srv/media"
      "/var/lib/jellyfin"
    ];
  };

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ port ];
}
