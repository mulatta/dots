{ pkgs, ... }:
{
  # Unused here, and SCTP is the nginx2root local root path.
  boot.extraModprobeConfig = ''
    install sctp ${pkgs.coreutils}/bin/false
  '';
}
