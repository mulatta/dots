{ pkgs, ... }:
{
  home.packages = with pkgs; [
    minio-client
    pueue
    ntfy-sh
  ];
}
