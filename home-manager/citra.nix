{
  pkgs,
  lib,
  self,
  ...
}:
let
  selfPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
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
  ];

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
