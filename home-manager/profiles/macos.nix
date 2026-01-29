{
  self,
  system,
  pkgs,
  ...
}:
{
  imports = [
    ../modules/calendar
    ../modules/keyboard
    ../modules/llm-agents.nix
    ../modules/mail
  ];

  home.packages = [
    self.packages.${system}.nextcloud-client
    self.packages.${system}.radicle-desktop
    pkgs.tailsacle
    pkgs.basalt
  ];
}
