{ pkgs, ... }:
{
  home.packages = with pkgs; [
    delta
    grex
    sd
    jq
    yq-go

    fd
    ripgrep
    xcp
    ouch
    dust

    procs
    htop
    hyperfine
  ];
}
