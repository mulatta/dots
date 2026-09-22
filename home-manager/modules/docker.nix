{
  pkgs,
  lib,
  ...
}:
{
  home.packages =
    with pkgs;
    [
      devcontainer
      docker-client
      docker-credential-helpers
      podman
      regctl
      skopeo
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.colima ];
}
