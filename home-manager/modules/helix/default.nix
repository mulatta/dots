# Helix editor - configs managed by stow (home/.config/helix/)
# Standalone is for `nix run .#helix` only
{
  pkgs,
  self,
  ...
}:
{
  home.packages = [
    pkgs.helix
    self.packages.${pkgs.stdenv.hostPlatform.system}.helix-lsp-tools
  ];
}
