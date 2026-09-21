{
  inputs,
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.kind
    pkgs.kubectl
    pkgs.kubectx
    inputs.sofka.packages.${pkgs.stdenv.hostPlatform.system}.sofka
  ];
}
