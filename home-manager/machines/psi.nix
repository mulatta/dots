{ ... }:
{
  imports = [
    ../modules/vscode/server.nix
  ];

  home.username = "seungwon";
  home.homeDirectory = "/home/seungwon";
}
