{ config, lib, ... }:
let
  paperlessPort = lib.toInt config.systemd.services.paperless-mcp.environment.MCP_PORT;
in
{
  containers.hermes.config.services.hermes.profiles.noa.mcpServers = {
    # User approval and refresh tokens stay in Hermes' mutable state, not Nix.
    trek = {
      url = "https://trek.mulatta.io/mcp";
      auth = "oauth";
    };
    # SparkyFitness issues user-scoped API keys rather than MCP OAuth tokens.
    sparkyfitness = {
      url = "https://fitness.mulatta.io/mcp";
      bearerTokenCredential = "noa-sparkyfitness-api-key";
    };
    paperless.url = "http://${config.containers.hermes.hostAddress}:${toString paperlessPort}/mcp";
  };
  # paperless-mcp binds every host interface itself; only the veth may reach it.
  networking.firewall.interfaces.ve-hermes.allowedTCPPorts = [ paperlessPort ];

  # Create the key in its UI before deployment; do not use an admin key.
  clan.core.vars.generators.hermes-sparkyfitness.prompts.api-key = {
    description = "SparkyFitness ordinary-user API key for Hermes MCP";
    type = "hidden";
    persist = true;
  };
}
