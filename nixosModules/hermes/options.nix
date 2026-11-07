# Option declarations only. Typed options exist where the module has to act
# on a value (env, credentials, files, packages); everything else goes into a
# freeform `settings`.
#
# Layers Hermes reads, from the module's point of view:
#   /etc/hermes/config.yaml, /etc/hermes/.env   services.hermes.{settings,environment}
#                                                 managed scope: every profile, wins over profile values
#   <profile home>/config.yaml                   services.hermes.profiles.<name>
#   <profile home>/.env -> /run/hermes/<name>.env profile environment + credentials, built at start
#   <profile home>/SOUL.md, skills/              mutable state, left to the agent and its owner
# Under a multiplexed gateway a routed profile never falls back to the process
# environment, so anything a profile needs lives in one of these files.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption mkEnableOption types;
  yaml = (pkgs.formats.yaml { }).type;

  modelType = types.submodule {
    options = {
      provider = mkOption {
        type = types.str;
        example = "openai-codex";
      };
      name = mkOption {
        type = types.str;
        example = "gpt-6.1-sol";
      };
      reasoningEffort = mkOption {
        type = types.nullOr (
          types.enum [
            "none"
            "minimal"
            "low"
            "medium"
            "high"
            "xhigh"
            "max"
          ]
        );
        default = null;
      };
    };
  };

  credential =
    default: description:
    mkOption {
      type = types.str;
      inherit default;
      description = "Name of the credential the host passes with --load-credential. ${description}";
    };

  # Behaviour shared by every chat platform.
  platformOptions = {
    homeChannel = mkOption {
      type = types.str;
      description = "Channel that receives proactive and cron messages.";
    };
    allowedUsers = mkOption {
      type = types.listOf types.str;
      description = "Users allowed to talk to the agent.";
    };
    progressMessages = mkEnableOption "interim messages and tool progress in chat";
    restartNotification = mkEnableOption "a chat notice when the gateway restarts";
  };

  profileType = types.submodule [
    config.services.hermes.profileDefaults
    (
      { name, ... }:
      let
        # Distinct per profile: two profiles may not poll the same bot token.
        cred = kind: credential "${name}-${kind}";
      in
      {
        options = {
          model = mkOption {
            type = modelType;
            description = "Main conversation model.";
          };

          platforms = {
            discord = platformOptions // {
              enable = mkEnableOption "Discord for profile ${name}";
              requireMention = mkOption {
                type = types.bool;
                default = true;
              };
              autoThread = mkOption {
                type = types.bool;
                default = true;
              };
              freeResponseChannels = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Channels answered without a mention. Not an access allowlist.";
              };
              botTokenCredential = cred "discord-bot-token" "Discord bot token.";
            };

          };

          mcpServers = mkOption {
            type = types.attrsOf (
              types.submodule {
                options = {
                  url = mkOption { type = types.str; };
                  auth = mkOption {
                    type = types.nullOr (types.enum [ "oauth" ]);
                    default = null;
                    description = "OAuth approval and refresh tokens stay in Hermes' mutable state.";
                  };
                  bearerTokenCredential = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "Credential sent as `Authorization: Bearer`.";
                  };
                };
              }
            );
            default = { };
          };

          auxiliary.tasks = mkOption {
            type = types.attrsOf modelType;
            default = { };
            description = "Model per side task (vision, compression, curator, ...). Per profile because provider logins are per profile.";
          };

          environment = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Non-secret values written to this profile's .env next to its credentials.";
          };

          credentials = mkOption {
            type = types.attrsOf types.str;
            default = { };
            example = {
              OPENROUTER_API_KEY = "noa-openrouter-api-key";
            };
            description = "Further .env variables read from host credentials, for settings that name an env var such as a provider's key_env.";
          };

          settings = mkOption {
            type = yaml;
            default = { };
            description = "Freeform values for this profile's config.yaml, merged over the typed options.";
          };
        };
      }
    )
  ];
in
{
  options.services.hermes = {
    enable = mkEnableOption "Hermes Agent";
    package = mkOption { type = types.package; };

    profileDefaults = mkOption {
      type = types.deferredModule;
      default = { };
      description = "Module applied to every profile, e.g. shared auxiliary models. Profiles can override it.";
    };
    defaultProfile = mkOption {
      type = types.str;
      description = "Profile served from $HERMES_HOME itself; the gateway and dashboard run as it.";
    };
    profiles = mkOption {
      type = types.attrsOf profileType;
      default = { };
    };

    requiredCredentials = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      description = "Credential names the gateway imports; the host passes each with --load-credential.";
    };
    uid = mkOption {
      type = types.int;
      default = 2001;
      description = "Must match the host so the bind-mounted state keeps its owner.";
    };
    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/hermes";
    };
    packages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Tools in the system profile, where Hermes' login shell finds them.";
    };
    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Non-secret values for /etc/hermes/.env, applied to every profile. Ends up in the nix store.";
    };

    # Read by the dashboard from the default profile.
    dashboard = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
      };
      port = mkOption {
        type = types.port;
        default = 9119;
      };
      publicUrl = mkOption { type = types.str; };
      oidc = {
        issuer = mkOption { type = types.str; };
        clientId = mkOption { type = types.str; };
        scopes = mkOption {
          type = types.listOf types.str;
          default = [
            "openid"
            "profile"
            "email"
          ];
        };
      };
    };

    memory.hindsight = {
      enable = mkEnableOption "the Hindsight memory provider";
      apiUrl = mkOption { type = types.str; };
      client = mkOption {
        type = types.package;
        description = "hindsight-client, built with Hermes' Python interpreter.";
      };
      plugins = mkOption {
        type = types.package;
        description = "Hindsight's integrations; the module links its `hermes` plugin.";
      };
      apiKeyCredential = credential "hindsight-api-key" "Hindsight API key, written to every profile's .env.";
    };

    browser.cdpUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    search.searxngUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    settings = mkOption {
      type = yaml;
      default = { };
      description = "Values for /etc/hermes/config.yaml: every profile, overriding profile values.";
    };
  };
}
