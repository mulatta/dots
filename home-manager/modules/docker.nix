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
      podman
      regctl
      skopeo
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.colima ];
}
