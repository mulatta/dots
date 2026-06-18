{
  config,
  pkgs,
  self,
  ...
}:
let
  # Kanidm OIDC settings
  kanidmDomain = "idm.mulatta.io";
  kanidmIssuer = "https://${kanidmDomain}/oauth2/openid/nextcloud";

  wgPrefix = self.lib.wgPrefix;
  # taps is the WireGuard controller (::1); it fronts nextcloud as reverse proxy
  tapsWgIP = "${wgPrefix}::1";
in
{
  disko.devices.zpool.zroot.datasets."nextcloud" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/nextcloud";
    options = {
      "com.sun:auto-snapshot" = "true";
    };
  };

  clan.core.vars.generators.nextcloud = {
    files.admin-password = {
      secret = true;
      owner = "nextcloud";
    };

    runtimeInputs = [ pkgs.openssl ];

    script = ''
      openssl rand -hex 24 > "$out/admin-password"
    '';
  };

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud33;
    hostName = "cloud.mulatta.io";

    config = {
      adminuser = "admin";
      adminpassFile = config.clan.core.vars.generators.nextcloud.files.admin-password.path;
      dbtype = "pgsql";
    };

    database.createLocally = true;
    configureRedis = true;

    settings = {
      overwriteprotocol = "https";
      trusted_proxies = [ tapsWgIP ];
      default_phone_region = "KR";
      maintenance_window_start = 3; # 3 AM UTC
      files_external_allow_create_new_local = true;
      # File-based logging for logreader app compatibility
      log_type = "file";
      logfile = "/var/lib/nextcloud/data/nextcloud.log";
      loglevel = 2; # 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
    };

    phpOptions = {
      "opcache.interned_strings_buffer" = "16";
    };

    extraApps = {
      rhwpviewer = self.inputs.rhwp-nextcloud.packages.${pkgs.stdenv.hostPlatform.system}.rhwp-viewer;
    };
    extraAppsEnable = true;
  };

  # ZFS auto-creates the dataset root-owned; reset it to the service user.
  systemd.tmpfiles.rules = [
    "Z /var/lib/nextcloud 0750 nextcloud nextcloud -"
  ];

  # OIDC configuration via occ commands
  # Using Kanidm public client with PKCE (no client secret needed)
  systemd.services.nextcloud-oidc-config = {
    description = "Configure Nextcloud OIDC integration with Kanidm";
    after = [ "nextcloud-setup.service" ];
    wantedBy = [ "multi-user.target" ];

    path = [ config.services.nextcloud.occ ];

    script = ''
      # Enable OIDC app
      nextcloud-occ app:enable user_oidc || true

      # user_oidc requires the clientsecret flag even for a PKCE public client,
      # so pass an empty string.
      nextcloud-occ user_oidc:provider kanidm \
        --clientid="nextcloud" \
        --clientsecret="" \
        --discoveryuri="${kanidmIssuer}/.well-known/openid-configuration" \
        --scope="openid email profile groups" \
        --unique-uid="0" \
        --mapping-uid="preferred_username" \
        --mapping-display-name="name" \
        --mapping-email="email" \
        --check-bearer="0"
    '';

    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      RemainAfterExit = true;
    };
  };

  # Allow access from WireGuard interface
  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ 80 ];
}
