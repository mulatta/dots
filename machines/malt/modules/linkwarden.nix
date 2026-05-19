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

  port = 3000;
  domain = "links.mulatta.io";
  kanidmDomain = "idm.mulatta.io";
in
{
  disko.devices.zpool.zroot.datasets."linkwarden" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/linkwarden";
    options = {
      compression = "lz4";
      recordsize = "128K";
      "com.sun:auto-snapshot" = "true";
    };
  };

  clan.core.vars.generators.linkwarden = {
    files.nextauth-secret = {
      secret = true;
      owner = "linkwarden";
      group = "linkwarden";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -base64 32 | tr -d '\n=' > "$out/nextauth-secret"
    '';
  };

  clan.core.vars.generators.kanidm-linkwarden-oidc = {
    share = true;
    files.secret = {
      secret = true;
      owner = "linkwarden";
      group = "linkwarden";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };

  services.linkwarden = {
    enable = true;
    host = maltWgIP;
    inherit port;
    openFirewall = false;
    enableRegistration = false;

    database.createLocally = true;

    secretFiles = {
      NEXTAUTH_SECRET = config.clan.core.vars.generators.linkwarden.files.nextauth-secret.path;
      AUTHENTIK_CLIENT_SECRET = config.clan.core.vars.generators.kanidm-linkwarden-oidc.files.secret.path;
    };

    environment = {
      NEXTAUTH_URL = "https://${domain}/api/v1/auth";
      NEXT_PUBLIC_CREDENTIALS_ENABLED = "false";

      # Linkwarden exposes only provider-specific OIDC integrations. Its
      # Authentik provider is standard OIDC, so Kanidm can back it directly.
      NEXT_PUBLIC_AUTHENTIK_ENABLED = "true";
      AUTHENTIK_CUSTOM_NAME = "Kanidm";
      AUTHENTIK_ISSUER = "https://${kanidmDomain}/oauth2/openid/linkwarden";
      AUTHENTIK_CLIENT_ID = "linkwarden";
    };
  };

  systemd.tmpfiles.rules = [
    "Z /var/lib/linkwarden 0750 linkwarden linkwarden -"
  ];

  systemd.services.linkwarden = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    unitConfig.RequiresMountsFor = [ "/var/lib/linkwarden" ];
  };

  systemd.services.linkwarden-worker = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    unitConfig.RequiresMountsFor = [ "/var/lib/linkwarden" ];
  };

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ port ];
}
