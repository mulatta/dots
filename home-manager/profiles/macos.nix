{ pkgs, self, ... }:
{
  imports = [
    ../modules/ghostty.nix
    ../modules/vscode
    ../modules/stylix.nix
  ];

  home.packages = with pkgs; [
    self.packages.${pkgs.stdenv.hostPlatform.system}.spacedrive
  ];
}
