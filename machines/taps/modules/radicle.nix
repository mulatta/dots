# Seed node configuration for taps
# Public-facing node with httpd web UI and GitHub sync endpoint
{ config, ... }:
{
  imports = [
    ../../../nixosModules/radicle-mulatta.nix
    ../../../nixosModules/radicle-github-sync.nix
  ];

  services.radicle = {
    httpd = {
      enable = true;
      listenAddress = "127.0.0.1";
      listenPort = 8889;
    };

    settings.node.externalAddresses = [ "64.176.225.253:8776" ];

    # SSH-based GitHub sync endpoint (disabled - needs testing)
    githubSync = {
      enable = false;
      repos = [
        {
          name = "mulatta-dots";
          repoId = "z4SMvWSqp66q9fMnmvbZ2uhWmn28y";
          githubUrl = "https://github.com/mulatta/dots";
          branch = "main";
          publicKeyFile =
            config.clan.core.vars.generators.radicle-sync-mulatta-dots.files.ssh-public-key.path;
          privateKeyFile =
            config.clan.core.vars.generators.radicle-sync-mulatta-dots.files.ssh-private-key.path;
        }
      ];
    };
  };
}
