{
  pkgs,
  self,
  ...
}:
{
  imports = [
    ../modules/ghostty.nix
    ../modules/mail
    ../modules/stylix.nix
    ../modules/thunderbird.nix
    ../modules/vscode
  ];

  home.packages = [
    self.packages.${pkgs.stdenv.hostPlatform.system}.spacedrive
  ];
}
