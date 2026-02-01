{
  self,
  system,
  pkgs,
  ...
}:
{
  imports = [
    ../modules/mail
    ../modules/calendar
    ../modules/keyboard
    ../modules/llm-agents.nix
  ];

  home.packages = [
    self.packages.${system}.nextcloud-client
    self.packages.${system}.radicle-desktop
    pkgs.tailsacle
  ];
}
