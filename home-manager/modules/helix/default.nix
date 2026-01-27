# Helix editor - configs managed by stow (home/.config/helix/)
# Standalone is for `nix run .#helix` only
{
  pkgs,
  self,
  ...
}:
let
  inherit (self.legacyPackages.${pkgs.stdenv.hostPlatform.system}) helix-lsp-tools;
in
{
  home.packages = [
    pkgs.helix
    helix-lsp-tools
  ];
}
