{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.programs.claude-desktop;
  jsonFormat = pkgs.formats.json { };

  configDir =
    if (pkgs.stdenv.isDarwin) then
      "${config.home.homeDirectory}/Library/Application Support/Claude"
    else
      "${config.xdg.configHome}/Claude";
  configFile = "${configDir}/claude_desktop_config.json";
in
{
  options.claude-desktop = {
    enable = lib.mkEnableOption "Use claude-desktop";
    packages = lib.mkPackageOption inputs.nix-ai-tools "claude-desktop" { nullable = true; };
    mcpServers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            command = lib.mkOption {
              type = lib.types.str;
              description = "Command to execute for the MCP server";
              example = "npx";
            };

            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Arguments to pass to the command";
              example = [
                "-y"
                "@modelcontextprotocol/server-filesystem"
                "/tmp"
              ];
            };

            env = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Environment variables to set for the MCP server";
              example = {
                PATH = "/usr/bin:/bin";
                API_KEY = "your-api-key";
              };
            };

            extraConfig = lib.mkOption {
              inherit (jsonFormat) type;
              default = { };
              description = "Additional configuration options for the MCP server";
              example = {
                timeout = 30;
                retries = 3;
              };
            };
          };
        }
      );
      default = { };
      description = "MCP (Model Context Protocol) servers configuration";
      example = {
        filesystem = {
          command = "npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-filesystem"
            "/Users/username/Documents"
          ];
          env = {
            PATH = "/usr/bin:/bin";
          };
        };
        perplexity = {
          command = "uvx";
          args = [ "perplexity-mcp" ];
          env = {
            PERPLEXITY_API_KEY = "your-api-key";
            PERPLEXITY_MODEL = "sonar-pro";
          };
        };
        docker-service = {
          command = "docker";
          args = [
            "run"
            "-i"
            "--rm"
            "some/mcp-server:latest"
          ];
          extraConfig = {
            timeout = 60;
            restart = true;
          };
        };
      };
    };

    package = lib.mkPackageOption pkgs "claude-desktop" {
      nullable = true;
      example = "pkgs.claude-desktop";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.mcpServers != { }
          -> (builtins.any (server: server.command != "") (builtins.attrValues cfg.mcpServers));
        message = "All MCP servers must have a non-empty command";
      }
    ];

    home = {
      packages = lib.mkIf (cfg.package != null) [ cfg.package ];

      file."${configFile}" = lib.mkIf (cfg.mcpServers != { } || cfg.settings != { }) {
        source = jsonFormat.generate "claude_desktop_config.json" (
          cfg.settings
          // lib.optionalAttrs (cfg.mcpServers != { }) {
            mcpServers = lib.mapAttrs (
              _name: serverCfg:
              {
                inherit (serverCfg) command;
              }
              // lib.optionalAttrs (serverCfg.args != [ ]) {
                inherit (serverCfg) args;
              }
              // lib.optionalAttrs (serverCfg.env != { }) {
                inherit (serverCfg) env;
              }
              // serverCfg.extraConfig
            ) cfg.mcpServers;
          }
        );
      };
    };
  };
}
