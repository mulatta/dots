{
  imports = [
    ../modules/vscode/server.nix
  ];

  home.username = "seungwon";
  home.homeDirectory = "/home/seungwon";

  home.sessionVariables = {
    NIKS3_SERVER_URL = "https://niks3.mulatta.io";
  };
}
