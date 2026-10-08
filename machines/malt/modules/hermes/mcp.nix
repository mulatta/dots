{ ... }:
{
  # User approval and refresh tokens stay in Hermes' mutable state, not Nix.
  services.hermes.settings.mcp_servers.trek = {
    url = "https://trek.mulatta.io/mcp";
    auth = "oauth";
  };
}
