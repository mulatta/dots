# Base Radicle node configuration
# Provides common settings for all radicle nodes
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.radicle;
in
{
  options.services.radicle = {
    seedRepositories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of Radicle repository IDs to automatically seed.";
      example = [ "rad:z2dqRKkK5yu89w3CMX2dVsYrRwvFk" ];
    };

    autoSeedFollowed = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically discover and seed repositories from followed users.";
    };

    followDids = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of DIDs to follow. Repos from these users will be accepted.";
      example = [ "did:key:z6MkkV8YjYkBowG8oFyMqwe1Lnp3B9TmJtTSjNNFY6mcxGJY" ];
    };

    connectNodes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of nodes to maintain persistent connections with (NID@host:port).";
      example = [ "z6MkkV8YjYkBowG8oFyMqwe1Lnp3B9TmJtTSjNNFY6mcxGJY@rad.mulatta.io:8776" ];
    };
  };

  config = {
    environment.systemPackages = [ pkgs.radicle-node ];

    # SSH key generation via clan vars
    clan.core.vars.generators.radicle = {
      files.ssh-private-key = {
        secret = true;
        owner = "radicle";
      };
      files.ssh-public-key.secret = false;
      runtimeInputs = [ pkgs.openssh ];
      script = ''
        ssh-keygen -t ed25519 -N "" -f $out/ssh-private-key -C "radicle@${config.networking.hostName}"
        ssh-keygen -y -f $out/ssh-private-key > $out/ssh-public-key
      '';
    };

    services.radicle = {
      enable = true;
      privateKeyFile = config.clan.core.vars.generators.radicle.files.ssh-private-key.path;
      publicKey = builtins.readFile config.clan.core.vars.generators.radicle.files.ssh-public-key.path;

      node = {
        openFirewall = true;
        listenAddress = "[::]";
        listenPort = 8776;
      };

      settings = {
        preferredSeeds = [
          "z6MkrLMMsiPWUcNPHcRajuMi9mDfYckSoJyPwwnknocNYPm7@seed.radicle.xyz:8776"
          "z6Mkmqogy2qEM2ummccUthFEaaHvyYmYBYh3dbe9W4ebScxo@iris.radicle.xyz:8776"
        ];
        node = {
          alias = config.networking.hostName;
          seedingPolicy = {
            default = "block";
            scope = "all";
          };
          follow = cfg.followDids;
          connect = cfg.connectNodes;
        };
        web.pinned.repositories = cfg.seedRepositories;
      };
    };

    # Initialize follow policies and seed repositories on startup
    systemd.services.radicle-node-setup =
      lib.mkIf (cfg.followDids != [ ] || cfg.seedRepositories != [ ])
        {
          description = "Initialize Radicle node follow policies and seed repositories";
          after = [ "radicle-node.service" ];
          wants = [ "radicle-node.service" ];
          wantedBy = [ "multi-user.target" ];
          environment = {
            HOME = "/var/lib/radicle";
            RAD_HOME = "/var/lib/radicle";
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "radicle";
            Group = "radicle";
            LoadCredential = "radicle:${config.clan.core.vars.generators.radicle.files.ssh-private-key.path}";
            BindReadOnlyPaths = [
              "${cfg.configFile}:/var/lib/radicle/config.json"
              "/run/credentials/radicle-node-setup.service/radicle:/var/lib/radicle/keys/radicle"
              "${config.clan.core.vars.generators.radicle.files.ssh-public-key.path}:/var/lib/radicle/keys/radicle.pub"
            ];
            StateDirectory = "radicle";
            StateDirectoryMode = "0750";
          };
          path = [ cfg.package ];
          script = ''
            for i in {1..30}; do
              if rad node status &>/dev/null; then break; fi
              sleep 1
            done
            ${lib.concatMapStringsSep "\n" (did: "rad follow ${lib.escapeShellArg did} || true") cfg.followDids}
            ${lib.concatMapStringsSep "\n" (
              rid: "rad seed ${lib.escapeShellArg rid} --scope all || true"
            ) cfg.seedRepositories}
          '';
        };

    # Periodic auto-seed of repos from followed users
    systemd.services.radicle-auto-seed = lib.mkIf cfg.autoSeedFollowed {
      description = "Auto-discover and seed repositories from followed users";
      after = [ "radicle-node.service" ];
      wants = [ "radicle-node.service" ];
      environment = {
        HOME = "/var/lib/radicle";
        RAD_HOME = "/var/lib/radicle";
      };
      serviceConfig = {
        Type = "oneshot";
        User = "radicle";
        Group = "radicle";
        LoadCredential = "radicle:${config.clan.core.vars.generators.radicle.files.ssh-private-key.path}";
        BindReadOnlyPaths = [
          "${cfg.configFile}:/var/lib/radicle/config.json"
          "/run/credentials/radicle-auto-seed.service/radicle:/var/lib/radicle/keys/radicle"
          "${config.clan.core.vars.generators.radicle.files.ssh-public-key.path}:/var/lib/radicle/keys/radicle.pub"
        ];
        StateDirectory = "radicle";
        StateDirectoryMode = "0750";
      };
      path = [ cfg.package ];
      script = ''
        rad follow 2>/dev/null | grep 'did:key:' | while read -r line; do
          nid=$(echo "$line" | sed 's/.*did:key:\([a-zA-Z0-9]*\).*/\1/')
          echo "Discovering repos from followed user $nid..."
          rad node inventory --nid "$nid" 2>/dev/null | while read -r rid; do
            if ! rad seed 2>/dev/null | grep -q "$rid"; then
              echo "Auto-seeding discovered repo: $rid"
              rad seed "$rid" --scope all || true
            fi
          done
        done
      '';
    };

    systemd.timers.radicle-auto-seed = lib.mkIf cfg.autoSeedFollowed {
      description = "Timer for auto-seeding repos from followed users";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "6h";
        RandomizedDelaySec = "10min";
      };
    };
  };
}
