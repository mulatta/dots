{ pkgs, ... }:
{
  networking.nftables.enable = true;

  # Keep iptables command for muscle memory / compatibility
  environment.systemPackages = [ pkgs.iptables ];
}
