{ config, ... }:
let
  youtube = config.services.flakelets.services.youtube-mcp.settings;
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
    youtube = {
      url = "http://${config.containers.hermes.hostAddress}:${toString youtube.port}/mcp";
      bearerTokenCredential = "noa-youtube-mcp-token";
    };
  };

  # Create the key in its UI before deployment; do not use an admin key.
  clan.core.vars.generators.hermes-sparkyfitness.prompts.api-key = {
    description = "SparkyFitness ordinary-user API key for Hermes MCP";
    type = "hidden";
    persist = true;
  };
}
