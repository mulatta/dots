{ config, ... }:
{
  # User approval and refresh tokens stay in Hermes' mutable state, not Nix.
  services.hermes.settings.mcp_servers.trek = {
    url = "https://trek.mulatta.io/mcp";
    auth = "oauth";
  };

  # SparkyFitness issues user-scoped API keys rather than MCP OAuth tokens.
  # Create the key in its UI before deployment; do not use an admin key.
  clan.core.vars.generators.hermes-sparkyfitness = {
    files.api-key.secret = true;
    prompts.api-key = {
      description = "SparkyFitness ordinary-user API key for Hermes MCP";
      type = "hidden";
    };
    script = ''
      cp "$prompts/api-key" "$out/api-key"
    '';
  };

  services.hermes.credentials.sparkyfitness-api-key = {
    file = config.clan.core.vars.generators.hermes-sparkyfitness.files.api-key.path;
    env = "SPARKYFITNESS_API_KEY";
  };
  services.hermes.settings.mcp_servers.sparkyfitness = {
    url = "https://fitness.mulatta.io/mcp";
    headers.Authorization = "Bearer \${SPARKYFITNESS_API_KEY}";
  };
}
