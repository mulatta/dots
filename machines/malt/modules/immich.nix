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

  # OAuth client secret (generated on malt, hash shared to taps)
  clan.core.vars.generators.immich-oauth = {
    files."client-secret" = {
      secret = true;
      owner = "immich";
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

      # OAuth via Authelia (client_secret set via UI)
      oauth = {
        enabled = true;
        issuerUrl = "https://auth.mulatta.io";
        clientId = "immich";
        scope = "openid email profile";
        buttonText = "Login with Authelia";
        autoRegister = true;
      };
    };
  };

  # Ensure correct ownership for ZFS dataset
  systemd.tmpfiles.rules = [
    "Z /var/lib/immich 0750 immich immich -"
  ];

  # Inject OAuth client secret into config.json at runtime
  systemd.services.immich-server.serviceConfig.ExecStartPre =
    let
      clientSecretPath = config.clan.core.vars.generators.immich-oauth.files."client-secret".path;
      injectScript = pkgs.writeShellScript "inject-oauth-secret" ''
        if [ -f "${clientSecretPath}" ]; then
          CLIENT_SECRET=$(cat "${clientSecretPath}")
          ${pkgs.jq}/bin/jq --arg secret "$CLIENT_SECRET" '.oauth.clientSecret = $secret' \
            /run/immich/config.json > /run/immich/config.json.tmp
          mv /run/immich/config.json.tmp /run/immich/config.json
        fi
      '';
    in
    pkgs.lib.mkAfter [ injectScript ];

  # Firewall: allow access from WireGuard network
  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ 2283 ];
}
