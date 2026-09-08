{
  self,
  config,
  pkgs,
  ...
}:
{

  clan.core.vars.generators.rsshub-github = {
    files.env.secret = true;
    prompts.github-access-token = {
      description = "GitHub PAT for RSSHub GitHub GraphQL routes";
      type = "hidden";
    };
    script = ''
      printf 'GITHUB_ACCESS_TOKEN=%s\n' "$(cat "$prompts/github-access-token")" > "$out/env"
    '';
  };

  # Miniflux is the only RSSHub consumer; public/SSO exposure would leak feed
  # URLs or add unnecessary auth complexity for a localhost backend.
  # The remaining routes (inu/kosaf notices, github trending) are plain HTTP, so
  # no headless Chromium or rendering fonts are needed - the journal routes that
  # required them moved to publisher RSS + the on-demand paperfetch-cli path.
  services.rsshub = {
    enable = true;
    package = self.packages.${pkgs.stdenv.hostPlatform.system}.rsshub;
    secretFiles = [ config.clan.core.vars.generators.rsshub-github.files.env.path ];
    redis.enable = true;
    settings = {
      PORT = 1200;
      # LISTEN_INADDR_ANY defaults to false (loopback-only); keep default.
    };
  };

  # Miniflux pulls from RSSHub, so make sure RSSHub is up first when both
  # start at boot. `wants` keeps this advisory: a RSSHub failure must not
  # prevent Miniflux from serving the rest of its feeds.
  systemd.services.miniflux.wants = [ "rsshub.service" ];
  systemd.services.miniflux.after = [ "rsshub.service" ];
}
