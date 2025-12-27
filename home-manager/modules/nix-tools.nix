{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nixd # Nix LSP
    nixfmt-rfc-style # RFC style formatter
    nvd # Nix version differ
    nix-diff # Derivation differ
    nix-output-monitor # Better nix build output
    nurl # Generate nix fetcher calls
  ];
}
