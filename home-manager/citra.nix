{
  config,
  pkgs,
  lib,
  self,
  inputs,
  ...
}:
let
  selfPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  aiPkgs = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  ovis = aiPkgs.ovis.override { runtime = "herdr-core"; };
in
{
  imports = [
    ./modules/ai.nix
    ./modules/calendar
    ./modules/kubernetes.nix
    ./modules/mail
  ];

  home.packages = [
    selfPkgs.rbw-pinentry
    pkgs.kanidm_1_11
    pkgs.wl-clipboard
    ovis
  ];

  # No [Install]: `systemctl --user start ovis` when needed; nginx serves it to the tailnet.
  systemd.user.services.ovis = {
    Unit.Description = "ovis web UI for herdr-core";
    Service = {
      ExecStart = lib.getExe ovis;
      # hc may start the core from here, and its terminals should see the login PATH.
      Environment = "PATH=${
        lib.concatStringsSep ":" [
          "/run/wrappers/bin"
          "${config.home.profileDirectory}/bin"
          "/run/current-system/sw/bin"
        ]
      }";
    };
  };

  # The RDP session draws on a virtual monitor, not the TV, and RDP credentials
  # already gate it; a lock on every reconnect only repeats the login.
  dconf.enable = true;
  dconf.settings = {
    "org/gnome/desktop/screensaver".lock-enabled = false;
    "org/gnome/desktop/lockdown".disable-lock-screen = true;
  };

  # Caches the master password in KWallet (TPM-unlocked) for mail and calendar sync.
  programs.rbw.settings = {
    pinentry = lib.mkForce selfPkgs.rbw-pinentry;
    lock_timeout = lib.mkForce 3600;
  };
}
