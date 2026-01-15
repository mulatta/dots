# Helix editor - configs managed by stow (home/.config/helix/)
{
  pkgs,
  self,
  ...
}:
{
  home.packages = [
    self.packages.${pkgs.stdenv.hostPlatform.system}.helix
  ];
}
