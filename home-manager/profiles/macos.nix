{ config, ... }:
{
  imports = [
    ../modules/ghostty.nix
    ../modules/mail
    ../modules/thunderbird.nix
    ../modules/vscode
  ];

  # macOS stylix targets
  stylix.targets.firefox = {
    enable = true;
    colorTheme.enable = true;
    profileNames = [ config.home.username ];
  };
}
