{ pkgs, ... }:
with pkgs.yaziPlugins;
{
  chmod = chmod;
  full-border = full-border;
  toggle-pane = toggle-pane;
  diff = diff;
  rsync = rsync;
  miller = miller;
  starship = starship;
  glow = glow;
  git = git;
  piper = piper;
}
