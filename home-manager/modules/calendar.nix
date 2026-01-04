{ pkgs, ... }:
{
  home.packages = with pkgs; [
    vdirsyncer
    khal
    todoman
    khard
  ];
}
