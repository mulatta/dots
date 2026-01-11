{
  config,
  pkgs,
  ...
}:
let
  # Kanidm OIDC settings
  kanidmDomain = "idm.mulatta.io";
  kanidmIssuer = "https://${kanidmDomain}/oauth2/openid/nextcloud";
in
{
  # ZFS dataset for Nextcloud data
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

  # Note: OAuth client secret not needed - using Kanidm public client with PKCE

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud32;
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
      trusted_proxies = [ "fd28:387a:57:8f00::1" ];
      default_phone_region = "KR";
    };
  };

  # Ensure correct ownership for ZFS dataset
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

      # Create or update provider (public client - no secret needed)
      # Nextcloud user_oidc app may require a secret even for public clients
      # Use a placeholder or empty string if PKCE is supported
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
