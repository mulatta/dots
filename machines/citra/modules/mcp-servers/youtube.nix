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
        allowedHosts = [
          "localhost"
          "127.0.0.1"
          config.containers.hermes.hostAddress
        ];
        tokenFile = config.clan.core.vars.generators.youtube-mcp.files.token.path;
      };
    };
  };
}
