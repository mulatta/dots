{
  config,
  lib,
  pkgs,
  ...
}:
{
  homebrew.enable = true;
  system.activationScripts.homebrew.text = lib.mkIf config.homebrew.enable (
    lib.mkBefore ''
      if [[ ! -f "${config.homebrew.prefix}/bin/brew" ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
    ''
  );

  # --no-quarantine was removed in Homebrew 5.0 (2025-09-22); no replacement.
  homebrew.onActivation.cleanup = "uninstall";
  homebrew.onActivation.upgrade = true;
  homebrew.brews = [ "mas" ];

  homebrew.casks = [
    # keep-sorted start
    "aldente"
    "alt-tab"
    "bitwarden"
    "chatgpt"
    "claude"
    "cleanshot"
    "codex-app"
    "devonthink"
    "gureumkim"
    "hancom-word"
    "hookmark"
    "logi-options+"
    "microsoft-excel"
    "microsoft-powerpoint"
    "microsoft-word"
    "nextcloud"
    "onedrive"
    "raycast"
    "secretive"
    "slack"
    "zerotier-one"
    "zoom"
    # keep-sorted end
  ];

  # App Store apps are managed declaratively by ../app-store/, which uses
  # nixpkgs' `mas` directly so we don't depend on Homebrew's mas integration
  # (the brew bundle path fails when mas itself is not yet installed).

  # Secretive SSH agent
  environment.etc."ssh/ssh_config.d/secretive.conf".text = ''
    Host *
      IdentityAgent ~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
  '';

  # Ghostty terminal requires Nerd Fonts
  fonts.packages = [ pkgs.nerd-fonts.fira-code ];
}
