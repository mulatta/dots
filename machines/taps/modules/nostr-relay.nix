{
  pkgs,
  ...
}:
let
  strfryPort = 7777;
  domain = "relay.mulatta.io";
in
{
  environment.etc."strfry.conf".text = ''
    db = "/var/lib/strfry/"

    relay {
      bind = "127.0.0.1"
      port = ${toString strfryPort}

      info {
        name = "Nostr Relay on ${domain}"
        description = "Private Nostr relay"
        contact = ""
      }

      nofiles = 0
      maxWebsocketPayloadSize = 131072
      autoPingSeconds = 55
      enableTCPKeepalive = false

      writePolicy {
        plugin = ""
      }
    }
  '';

  systemd.services.strfry = {
    description = "strfry Nostr relay";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.strfry}/bin/strfry --config=/etc/strfry.conf relay";
      Restart = "on-failure";
      RestartSec = 5;

      DynamicUser = true;
      StateDirectory = "strfry";

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ReadWritePaths = [ "/var/lib/strfry" ];
    };
  };
}
