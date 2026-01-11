{
  pkgs,
  self,
  ...
}:
{
  home.packages = [
    pkgs.radicle-node
    self.packages.${pkgs.stdenv.hostPlatform.system}.gh-radicle
    self.packages.${pkgs.stdenv.hostPlatform.system}.create-gh-app
  ];

  # Git alias for rad patch
  programs.git.settings.alias.patch = "push rad HEAD:refs/patches";
}
