{
  self,
  pkgs,
  ...
}:
{
  imports = [
    ./modules/chat.nix
  ];

  # ChatGPT remote workspaces require Codex in the remote login shell.
  home.packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.codex ];
}
