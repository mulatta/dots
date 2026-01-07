{ pkgs, ... }:
{
  home.packages = with pkgs; [
    isync
    notmuch
    afew
    aerc
    mblaze
    w3m
  ];
}
