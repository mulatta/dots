{
  self,
  config,
  pkgs,
  ...
}:
let
  clanLib = self.inputs.clan-core.lib;

  wgPrefix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "taps";
    generator = "wireguard-network-wireguard";
    file = "prefix";
  };
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";

  # Kanidm OIDC settings
  kanidmDomain = "idm.mulatta.io";
in
{
  # ZFS dataset for immich media storage
  disko.devices.zpool.zroot.datasets."immich" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/immich";
    options = {
      compression = "off"; # Media files are already compressed
      recordsize = "1M"; # Optimize for large files
      "com.sun:auto-snapshot" = "true";
    };
  };

  # Secrets generation
  clan.core.vars.generators.immich = {
    files.env = {
      secret = true;
      owner = "immich";
    };
    runtimeInputs = with pkgs; [
      coreutils
      openssl
    ];
    script = ''
      DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n=')
      echo "DB_PASSWORD=$DB_PASSWORD" > "$out/env"
    '';
  };

  # Note: OAuth client secret not needed - using Kanidm public client with PKCE

  # Immich service
  services.immich = {
    enable = true;
    port = 2283;
    host = maltWgIP;
    mediaLocation = "/var/lib/immich";

    # Database and cache
    database.enable = true;
    redis.enable = true;

    # Machine learning with Intel GPU acceleration
    machine-learning.enable = true;
    accelerationDevices = [ "/dev/dri/renderD128" ];

    # Secrets
    secretsFile = config.clan.core.vars.generators.immich.files.env.path;

    # Settings
    settings = {
      server.externalDomain = "https://immich.mulatta.io";
      newVersionCheck.enabled = false;

      # OAuth via Kanidm (public client with PKCE - no secret needed)
      oauth = {
        enabled = true;
        issuerUrl = "https://${kanidmDomain}/oauth2/openid/immich";
        clientId = "immich";
        scope = "openid email profile";
        buttonText = "Login with Kanidm";
        autoRegister = true;
        # Public client uses PKCE, no clientSecret needed
      };
    };
  };

  # Ensure correct ownership for ZFS dataset
  systemd.tmpfiles.rules = [
    "Z /var/lib/immich 0750 immich immich -"
  ];

  # Firewall: allow access from WireGuard network
  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ 2283 ];
}
