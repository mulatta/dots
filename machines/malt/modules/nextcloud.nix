{
  config,
  pkgs,
  ...
}:
let
  # Use .x domain for WireGuard mesh access
  autheliaIssuer = "https://auth.mulatta.io";
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

  # OAuth client secret (generated on malt, hash shared to taps)
  clan.core.vars.generators.nextcloud-oauth = {
    files."client-secret" = {
      secret = true;
      owner = "nextcloud";
    };
    files."client-secret-hash".secret = false; # Public for taps to read
    runtimeInputs = with pkgs; [
      openssl
      authelia
      gnused
    ];
    script = ''
      SECRET=$(openssl rand -base64 32 | tr -d '\n=')
      echo -n "$SECRET" > "$out/client-secret"
      authelia crypto hash generate argon2 --password "$SECRET" | sed 's/^Digest: //' | tr -d '\n' > "$out/client-secret-hash"
    '';
  };

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud32;
    hostName = "nextcloud.mulatta.io";

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
  systemd.services.nextcloud-oidc-config = {
    description = "Configure Nextcloud OIDC integration";
    after = [ "nextcloud-setup.service" ];
    wantedBy = [ "multi-user.target" ];

    path = [ config.services.nextcloud.occ ];

    script = ''
      # Enable OIDC app
      nextcloud-occ app:enable user_oidc || true

      # Get client secret
      CLIENT_SECRET=$(cat ${config.clan.core.vars.generators.nextcloud-oauth.files."client-secret".path})

      # Create or update provider
      nextcloud-occ user_oidc:provider authelia \
        --clientid="nextcloud" \
        --clientsecret="$CLIENT_SECRET" \
        --discoveryuri="${autheliaIssuer}/.well-known/openid-configuration" \
        --scope="openid email profile" \
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
