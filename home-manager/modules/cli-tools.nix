{ pkgs, ... }:
{
  home.packages = with pkgs; [
    delta # Git diff viewer
    fd # Find alternative
    grex # Regex generator
    ripgrep # Grep alternative
    sd # Sed alternative
    xcp # Cp with progress
    yq-go # YAML processor
  ];
}
