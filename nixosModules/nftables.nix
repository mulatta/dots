{ pkgs, ... }:
{
  # Use nftables instead of iptables (modern firewall)
  networking.nftables.enable = true;

  # Keep iptables command for muscle memory / compatibility
  environment.systemPackages = [ pkgs.iptables ];
}
