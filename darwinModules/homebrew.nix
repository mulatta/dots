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
      if [[ ! -f "${config.homebrew.brewPrefix}/brew" ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
    ''
  );

  # Don't quarantine apps installed by homebrew with gatekeeper
  homebrew.caskArgs.no_quarantine = true;
  # Remove all homebrew packages when they get removed from the configuration
  homebrew.onActivation.cleanup = "uninstall";
  # Upgrade outdated casks on darwin-rebuild
  homebrew.onActivation.upgrade = true;

  # Required for masApps
  homebrew.brews = [ "mas" ];

  homebrew.casks = [
    # keep-sorted start
    "1password"
    "aldente"
    "alt-tab"
    "claude"
    "cleanshot"
    "devonthink"
    "ghostty"
    "hancom-word"
    "hazel"
    "hookmark"
    "logi-options+"
    "microsoft-excel"
    "microsoft-powerpoint"
    "microsoft-word"
    "onedrive"
    "raycast"
    "secretive"
    "slack"
    "tailscale-app"
    "zen"
    "zoom"
    "zotero"
    # keep-sorted end
  ];

  # App Store apps (requires `mas` CLI and App Store login)
  homebrew.masApps = {
    "Goodnotes" = 1444383602;
    "KakaoTalk" = 869223134;
    "Perplexity" = 6714467650;
    "WireGuard" = 1451685025;
    "Xcode" = 497799835;
  };

  # Secretive SSH agent
  environment.etc."ssh/ssh_config.d/secretive.conf".text = ''
    Host *
      IdentityAgent ~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
  '';

  # Ghostty terminal requires Nerd Fonts
  fonts.packages = [ pkgs.nerd-fonts.fira-code ];
}
