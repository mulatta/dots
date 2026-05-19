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
  tapsWgIP = "${wgPrefix}::1";

  domain = "home.mulatta.io";
  port = 8123;
in
{
  disko.devices.zpool.zroot.datasets."home-assistant" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/hass";
    options."com.sun:auto-snapshot" = "true";
  };

  services.home-assistant = {
    enable = true;
    configDir = "/var/lib/hass";
    openFirewall = false;

    customComponents = [
      pkgs.home-assistant-custom-components.auth_oidc
    ];

    extraPackages = ps: [
      ps.psycopg2
    ];

    config = {
      default_config = { };

      homeassistant = {
        name = "Home";
        external_url = "https://${domain}";
        internal_url = "https://${domain}";
        unit_system = "metric";
        time_zone = "Asia/Seoul";
      };

      http = {
        server_host = maltWgIP;
        server_port = port;
        use_x_forwarded_for = true;
        trusted_proxies = [ tapsWgIP ];
        ip_ban_enabled = true;
        login_attempts_threshold = 5;
      };

      recorder.db_url = "postgresql://hass@/hass?host=/run/postgresql";

      auth_oidc = {
        client_id = "homeassistant";
        discovery_url = "https://idm.mulatta.io/oauth2/openid/homeassistant/.well-known/openid-configuration";
        display_name = "Kanidm";
        id_token_signing_alg = "RS256";
        features = {
          automatic_person_creation = true;
          force_https = true;
        };
        roles = {
          admin = "admins@idm.mulatta.io";
          user = "homeassistant_users@idm.mulatta.io";
        };
      };
    };
  };

  services.postgresql.ensureDatabases = [ "hass" ];
  services.postgresql.ensureUsers = [
    {
      name = "hass";
      ensureDBOwnership = true;
    }
  ];

  systemd.tmpfiles.rules = [
    "Z /var/lib/hass 0750 hass hass -"
  ];

  systemd.services.home-assistant = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    unitConfig.RequiresMountsFor = [ "/var/lib/hass" ];
  };

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ port ];
}
