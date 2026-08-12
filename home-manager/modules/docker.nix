{
  pkgs,
  lib,
  ...
}:
{
  home.packages = [
    pkgs.docker-client
    pkgs.docker-credential-helpers
    pkgs.regctl
  ]
  ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.colima ];
}
