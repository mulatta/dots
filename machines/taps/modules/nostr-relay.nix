{
  pkgs,
  ...
}:
let
  strfryPort = 7777;
  domain = "relay.mulatta.io";
  retentionDays = 90;

  # This relay is private: it only stores events authored by, or addressed to
  # (NIP-17 gift-wrap "p" tag), our own identities. Without this strfry accepts
  # everything, and on the open internet that fills the database with external
  # gift-wraps addressed to other people. Allowlist is derived from the shared
  # identity registry so it tracks new identities automatically.
  allowedPubkeys = lib.filter (k: k != null) (
    lib.mapAttrsToList (_: id: id.pubkey) config.mulatta.nostr.identities
  );
  # Pass the allowlist via a file (and the env var on the relay service) so the
  # plugin source stays static and the long hex keys live as data, not code.
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
  # Reuse the relay's hardening for the one-shot prune so it can write the db.
  strfryHardening = {
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
      # WebSocket clients are long-lived and each holds an fd; strfry.conf sets
      # nofiles=0 so it inherits this rather than raising it itself (which
      # DynamicUser can't do).
      LimitNOFILE = 65536;
    }
    // strfryHardening;
  };

  # Without pruning the LMDB database grows unbounded. Delete events older than
  # the retention window weekly. Note: LMDB never shrinks the file -- delete
  # only frees pages for reuse, capping further growth. Reclaiming disk needs a
  # one-off `strfry compact`.
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
