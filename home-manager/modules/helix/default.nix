# Helix editor - configs managed by stow (home/.config/helix/)
# Standalone is for `nix run .#helix` only
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    helix
    helix-lsp-tools
  ];
}
