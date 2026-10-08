# Server-side Buzz agents: identity, owner attestation, and the agent-signed
# profile events. Owner-signed registration (kind:30177) and channel membership
# need the owner key, which never reaches a machine; run `buzz-agents-sync`
# from the admin machine for those.
{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.buzz-agents;
  vars = config.clan.core.vars.generators;
  buzzCli = self.inputs.buzz.packages.${pkgs.stdenv.hostPlatform.system}.buzz-cli;

  agentModule =
    { name, config, ... }:
    {
      options = {
        displayName = mkOption {
          type = types.str;
          default = name;
          description = "Name shown for the agent on Buzz.";
        };
        avatar = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Profile picture URL; relay media must be metadata-free.";
        };
        channels = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Channel UUIDs the agent joins with the bot role.";
        };
        respondTo = mkOption {
          type = types.enum [
            "owner-only"
            "allowlist"
            "anyone"
          ];
          default = "owner-only";
          description = "Who Buzz Desktop lets mention the agent.";
        };
        addPolicy = mkOption {
          type = types.enum [
            "anyone"
            "owner_only"
            "nobody"
          ];
          default = "owner_only";
          description = "Who may add the agent to further channels.";
        };
        keyGenerator = mkOption {
          type = types.str;
          default = "buzz-agent-${name}";
          description = "Clan generator holding the agent key; renaming it rotates the identity.";
        };
        authGenerator = mkOption {
          type = types.str;
          default = "${config.keyGenerator}-auth";
          description = "Clan generator holding the owner attestation tag.";
        };
        before = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Units that should start after the agent profile is published.";
        };

        pubkey = mkOption {
          type = types.str;
          readOnly = true;
          default = vars.${config.keyGenerator}.files.public-key.value;
          description = "Agent public key (hex).";
        };
        privateKeyFile = mkOption {
          type = types.str;
          readOnly = true;
          default = vars.${config.keyGenerator}.files.private-key.path;
          description = "Host path of the agent secret key.";
        };
        authTagFile = mkOption {
          type = types.str;
          readOnly = true;
          default = vars.${config.authGenerator}.files.auth-tag.path;
          description = "Host path of the NIP-OA auth tag JSON.";
        };
      };
    };
in
{
  options.services.buzz-agents = {
    relayUrl = mkOption {
      type = types.str;
      description = "Buzz relay base URL (https://…).";
    };
    ownerPubkey = mkOption {
      type = types.str;
      description = "Hex public key of the relay owner who attests every agent.";
    };
    agents = mkOption {
      type = types.attrsOf (types.submodule agentModule);
      default = { };
      description = "Agents whose identities this machine holds.";
    };
  };

  config = lib.mkIf (cfg.agents != { }) {
    clan.core.vars.generators = lib.mkMerge (
      [
        {
          # The owner identity signs attestations. Generators read it on the
          # admin machine; deployments never receive it.
          buzz-owner-secret = {
            share = true;
            files.nsec = {
              secret = true;
              deploy = false;
            };
            prompts.nsec = {
              description = "Buzz owner's Nostr secret key (nsec or hex), from Buzz Desktop";
              type = "hidden";
            };
            script = ''
              tr -d '\r\n' < "$prompts/nsec" > "$out/nsec"
            '';
          };
        }
      ]
      ++ lib.mapAttrsToList (_: agent: {
        # Independent identity: never reuse the owner's or the relay's key.
        ${agent.keyGenerator} = {
          files.private-key.secret = true;
          files.public-key.secret = false;
          runtimeInputs = [ pkgs.nak ];
          script = ''
            umask 077
            nak key generate > "$out/private-key"
            nak key public < "$out/private-key" > "$out/public-key"
          '';
        };
        # The relay records the owner from this tag at AUTH, and Buzz Desktop
        # verifies it in the agent's profile before allowing mentions.
        ${agent.authGenerator} = {
          dependencies = [
            agent.keyGenerator
            "buzz-owner-secret"
          ];
          files.auth-tag.secret = true;
          runtimeInputs = [ (pkgs.python3.withPackages (p: [ p.coincurve ])) ];
          script = ''
            python3 ${./nip-oa-tag.py} \
              "$(cat "$in/${agent.keyGenerator}/public-key")" ${cfg.ownerPubkey} \
              < "$in/buzz-owner-secret/nsec" > "$out/auth-tag"
          '';
        };
      }) cfg.agents
    );

    systemd.services = lib.mapAttrs' (
      name: agent:
      lib.nameValuePair "buzz-agent-${name}-profile" {
        description = "Publish the Buzz agent profile of ${name}";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        inherit (agent) before;

        path = [ buzzCli ];
        environment = {
          BUZZ_RELAY_URL = cfg.relayUrl;
          HOME = "/tmp";
        };

        # Both events are replaceable, so republishing on every start is safe.
        script = ''
          BUZZ_PRIVATE_KEY=$(< "$CREDENTIALS_DIRECTORY/private-key")
          BUZZ_AUTH_TAG=$(< "$CREDENTIALS_DIRECTORY/auth-tag")
          export BUZZ_PRIVATE_KEY BUZZ_AUTH_TAG
          buzz users set-profile --name ${lib.escapeShellArg agent.displayName}${
            lib.optionalString (agent.avatar != null) " --avatar ${lib.escapeShellArg agent.avatar}"
          }
          buzz channels set-add-policy --policy ${agent.addPolicy}
        '';

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = 30;
          DynamicUser = true;
          LoadCredential = [
            "private-key:${agent.privateKeyFile}"
            "auth-tag:${agent.authTagFile}"
          ];
          PrivateTmp = true;
          CapabilityBoundingSet = "";
          LockPersonality = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectSystem = "strict";
          RestrictSUIDSGID = true;
        };
      }
    ) cfg.agents;
  };
}
