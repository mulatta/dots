{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nixd
    nixfmt-rfc-style
    nvd
    nix-diff
    nix-tree
    nix-output-monitor
    nix-prefetch
    nurl
    nixpkgs-review
  ];
}
