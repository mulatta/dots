{ config, pkgs, ... }:
{
  clan.core.vars.generators.searxng = {
    files.env.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      printf 'SEARX_SECRET_KEY=%s\n' "$(openssl rand -hex 32)" > "$out/env"
    '';
  };

  # Local agents need JSON without exposing an unauthenticated search proxy.
  services.searx = {
    enable = true;
    environmentFile = config.clan.core.vars.generators.searxng.files.env.path;
    openFirewall = false;
    configureNginx = false;
    settings = {
      use_default_settings = true;
      general.debug = false;
      server = {
        bind_address = "127.0.0.1";
        port = 8888;
        secret_key = "$SEARX_SECRET_KEY";
        limiter = false;
        public_instance = false;
      };
      search.formats = [
        "html"
        "json"
      ];
    };
  };
}
