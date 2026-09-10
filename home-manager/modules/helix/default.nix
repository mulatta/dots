# Helix editor with config managed by Stow under home/.config/helix/.
{
  pkgs,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  inherit (self.packages.${system}) helix;
  inherit (self.legacyPackages.${system}) helix-lsp-packages;
in
{
  home.packages = helix-lsp-packages ++ [ helix ];
}
