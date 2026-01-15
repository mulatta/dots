{
  pkgs,
  lib,
  self,
  ...
}: {
  home.packages =
    [
      self.packages.${pkgs.stdenv.hostPlatform.system}.yazi
    ]
    ++ lib.optionals (!pkgs.stdenv.isDarwin) [pkgs.fontpreview];
}
