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
  linkwardenDomain = "links.mulatta.io";
in
{
  # ZFS dataset for linkwarden data storage
  disko.devices.zpool.zroot.datasets."linkwarden" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/linkwarden";
    options = {
      compression = "lz4";
      recordsize = "128K";
      "com.sun:auto-snapshot" = "true";
    };
  };

  # Secrets generation
  clan.core.vars.generators.linkwarden = {
    files.env = {
      secret = true;
      owner = "linkwarden";
    };
    runtimeInputs = with pkgs; [
      coreutils
      openssl
    ];
    script = ''
      NEXTAUTH_SECRET=$(openssl rand -base64 32 | tr -d '\n=')
      DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n=')
      cat > "$out/env" <<EOF
      NEXTAUTH_SECRET=$NEXTAUTH_SECRET
      POSTGRES_PASSWORD=$DB_PASSWORD
      EOF
    '';
  };

  # Kanidm OAuth2 client secret (manually generated via kanidm CLI)
  clan.core.vars.generators.linkwarden-oidc = {
    files.client-secret = {
      secret = true;
      owner = "linkwarden";
    };
    prompts.client-secret = {
      description = "Linkwarden Kanidm OAuth2 client secret (run: kanidm system oauth2 show-basic-secret linkwarden)";
      type = "hidden";
    };
    script = ''
      cp "$prompts/client-secret" "$out/client-secret"
    '';
  };

  # Linkwarden service with Kanidm SSO
  services.linkwarden = {
    enable = true;
    port = 3000;
    host = maltWgIP;

    # Database
    database.createLocally = true;

    # Disable public registration (use SSO)
    enableRegistration = false;

    # Environment secrets
    environmentFile = config.clan.core.vars.generators.linkwarden.files.env.path;

    # SSO via Kanidm (using Authentik provider as generic OIDC)
    secretFiles = {
      AUTHENTIK_CLIENT_SECRET = config.clan.core.vars.generators.linkwarden-oidc.files.client-secret.path;
    };

    environment = {
      NEXTAUTH_URL = "https://${linkwardenDomain}";

      # Use Authentik provider settings for Kanidm (standard OIDC)
      NEXT_PUBLIC_AUTHENTIK_ENABLED = "true";
      AUTHENTIK_CUSTOM_NAME = "Kanidm";
      AUTHENTIK_ISSUER = "https://${kanidmDomain}/oauth2/openid/linkwarden";
      AUTHENTIK_CLIENT_ID = "linkwarden";
    };
  };

  # Ensure correct ownership for ZFS dataset
  systemd.tmpfiles.rules = [
    "Z /var/lib/linkwarden 0750 linkwarden linkwarden -"
  ];

  # Firewall: allow access from WireGuard network
  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ 3000 ];
}
