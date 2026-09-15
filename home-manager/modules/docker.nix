{
  pkgs,
  lib,
  ...
}:
{
  home.packages =
    with pkgs;
    [
      docker-client
      docker-credential-helpers
      regctl
      skopeo
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.colima ];
}
