{
  self,
  system,
  ...
}:
{
  imports = [
    ../modules/mail
    ../modules/calendar
    ../modules/llm-agents.nix
  ];

  home.packages = [
    self.packages.${system}.nextcloud-client
    self.packages.${system}.radicle-desktop
  ];
}
