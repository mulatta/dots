{
  config,
  lib,
  pkgs,
  ...
}:
let
  strfryPort = 7777;
  domain = "relay.mulatta.io";
  retentionDays = 90;

  # Without a policy strfry accepts unrelated gift-wrap traffic from the open
  # internet. Keep the relay scoped to our identities and direct p-tag traffic.
  allowedPubkeys = lib.filter (k: k != null) (
    lib.mapAttrsToList (_: id: id.pubkey) config.mulatta.nostr.identities
  );
  # Keep keys as data so identity changes do not rewrite the plugin source.
  allowlistFile = pkgs.writeText "strfry-allowlist.json" (builtins.toJSON allowedPubkeys);
  writePolicyPlugin = pkgs.writers.writePython3 "strfry-allowlist" { } ''
    import json
    import os
    import sys

    with open(os.environ["STRFRY_ALLOWLIST"]) as f:
        allow = set(json.load(f))

    while True:
        line = sys.stdin.readline()
        if not line:
            break
        event = json.loads(line)["event"]
        allowed = event["pubkey"] in allow or any(
            len(tag) >= 2 and tag[0] == "p" and tag[1] in allow
            for tag in event.get("tags", [])
        )
        print(
            json.dumps(
                {
                    "id": event["id"],
                    "action": "accept" if allowed else "reject",
                    "msg": "" if allowed else "blocked: relay is private",
                }
            ),
            flush=True,
        )
  '';
  strfryHardening = {
    DynamicUser = true;
    User = "strfry";
    Group = "strfry";
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
        plugin = "${writePolicyPlugin}"
      }

      logging {
        # Stale ephemeral replays flood journald without useful signal.
        invalidEvents = false
      }
    }
  '';

  systemd.services.strfry = {
    description = "strfry Nostr relay";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    # strfry execs plugins via `sh -c`, so keep a shell in the sandboxed PATH.
    path = [ pkgs.bash ];
    environment.STRFRY_ALLOWLIST = "${allowlistFile}";

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.strfry}/bin/strfry --config=/etc/strfry.conf relay";
      Restart = "on-failure";
      RestartSec = 5;
      # strfry.conf sets nofiles=0, so DynamicUser services need systemd to
      # raise the inherited fd limit.
      LimitNOFILE = 65536;
    }
    // strfryHardening;
  };

  # LMDB delete frees pages for reuse; shrinking the file needs manual compact.
  systemd.services.strfry-prune = {
    description = "Prune old strfry events";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.strfry}/bin/strfry --config=/etc/strfry.conf delete --age=${
        toString (retentionDays * 86400)
      }";
    }
    // strfryHardening;
  };

  systemd.timers.strfry-prune = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
