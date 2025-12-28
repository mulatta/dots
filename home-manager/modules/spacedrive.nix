{
  self,
  pkgs,
  lib,
  ...
}:
let
  supportedSystems = [
    "aarch64-darwin"
    "x86_64-linux"
  ];
  isSupported = builtins.elem pkgs.stdenv.hostPlatform.system supportedSystems;
in
{
  home.packages = lib.mkIf isSupported [
    self.packages.${pkgs.stdenv.hostPlatform.system}.spacedrive
  ];
}
