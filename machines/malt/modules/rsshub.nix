{
  config,
  lib,
  ...
}:
let
  cfg = config.services.rsshub;
  rsshubGithubEnv = config.clan.core.vars.generators.rsshub-github.files.env.path;
  rsshubPort = lib.toInt cfg.settings.PORT;

  interfaceFirewalls = lib.attrValues config.networking.firewall.interfaces;
  interfaceAllowedTCPPorts = lib.concatMap (iface: iface.allowedTCPPorts or [ ]) interfaceFirewalls;
  interfaceAllowedTCPPortRanges = lib.concatMap (
    iface: iface.allowedTCPPortRanges or [ ]
  ) interfaceFirewalls;

  portInRange = port: range: port >= range.from && port <= range.to;
  portAllowed =
    port:
    lib.elem port config.networking.firewall.allowedTCPPorts
    || lib.any (portInRange port) config.networking.firewall.allowedTCPPortRanges
    || lib.elem port interfaceAllowedTCPPorts
    || lib.any (portInRange port) interfaceAllowedTCPPortRanges;
in
{
  assertions = [
    {
      assertion = cfg.settings.LISTEN_INADDR_ANY == "0";
      message = "malt RSSHub must remain bound to loopback only.";
    }
    {
      assertion = !cfg.openFirewall && !(portAllowed rsshubPort);
      message = "malt RSSHub port must not be opened in the firewall.";
    }
    {
      assertion = cfg.secretFiles == [ rsshubGithubEnv ] && !(cfg.settings ? ACCESS_KEY);
      message = "malt RSSHub must only use the GitHub token secret file and no ACCESS_KEY.";
    }
    {
      assertion = cfg.redis.enable && cfg.redis.createLocally && cfg.redis.host == "localhost";
      message = "malt RSSHub must use the local Redis cache only.";
    }
    {
      assertion = !(portAllowed cfg.redis.port);
      message = "malt RSSHub Redis port must not be opened in the firewall.";
    }
  ];

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
  services.rsshub = {
    enable = true;
    secretFiles = [ rsshubGithubEnv ];
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
