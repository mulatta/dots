# MCP server declarations → final mcpServers attrset
# `secrets` field: { ENV_NAME = "rbw-entry-name"; }
# → automatically wrapped with rbw secret injection at runtime
{
  pkgs,
  lib,
}:
let
  uvx = "${pkgs.uv}/bin/uvx";
  npx = "${pkgs.nodejs_24}/bin/npx";
  rbw = "${pkgs.rbw}/bin/rbw";

  # Wrap a stdio command with rbw secret injection
  wrapWithSecrets =
    name: cfg:
    let
      exportLines = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          envVar: entry: "export ${envVar}=$(${rbw} get ${lib.escapeShellArg entry})"
        ) cfg.secrets
      );
    in
    pkgs.writeShellScript "mcp-${name}" ''
      ${exportLines}
      exec ${cfg.command} ${lib.escapeShellArgs (cfg.args or [ ])}
    '';

  # Convert a server declaration to mcpServers JSON entry
  toMcpServer =
    name: cfg:
    if cfg.type or "stdio" == "http" then
      {
        type = "http";
        url = cfg.url;
      }
    else
      let
        hasSecrets = cfg ? secrets && cfg.secrets != { };
        command = if hasSecrets then "${wrapWithSecrets name cfg}" else cfg.command;
        args = if hasSecrets then [ ] else cfg.args or [ ];
      in
      { inherit command args; } // lib.optionalAttrs (cfg ? env) { inherit (cfg) env; };
in
{
  mcpServers = lib.mapAttrs toMcpServer {
    deepwiki = {
      type = "http";
      url = "https://mcp.deepwiki.com/mcp";
    };

    docling = {
      command = uvx;
      args = [
        "--from=docling-mcp"
        "docling-mcp-server"
      ];
    };

    nixos = {
      command = uvx;
      args = [ "mcp-nixos" ];
    };

    pubmedmcp = {
      command = uvx;
      args = [ "pubmedmcp@latest" ];
    };

    ck-search = {
      command = "${pkgs.ck}/bin/ck";
      args = [ "--serve" ];
    };

    perplexity = {
      command = uvx;
      args = [ "perplexity-mcp" ];
      env.PERPLEXITY_MODEL = "sonar-pro";
      secrets.PERPLEXITY_API_KEY = "perplexity-api";
    };

    n8n-mcp = {
      command = npx;
      args = [ "n8n-mcp" ];
      env = {
        N8N_API_URL = "https://n8n-api.mulatta.io";
        DISABLE_CONSOLE_OUTPUT = "true";
      };
      secrets.N8N_API_KEY = "n8n-api";
    };

    qmd = {
      command = "${pkgs.qmd}/bin/qmd";
      args = [ "mcp" ];
    };
  };
}
