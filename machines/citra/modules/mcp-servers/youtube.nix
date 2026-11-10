{ config, pkgs, ... }:
{
  clan.core.vars.generators.youtube-mcp = {
    files.token.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/token"
    '';
  };

  services.flakelets = {
    enable = true;
    services.youtube-mcp = {
      flake = "github:mulatta/mcp-servers";
      output = "flakelets.youtube";
      autoUpdate.enable = true;
      settings = {
        port = 8765;
        tokenFile = config.clan.core.vars.generators.youtube-mcp.files.token.path;
      };
    };
  };
}
