{
  config,
  lib,
  self,
  ...
}:
let
  rhesus = self.darwinConfigurations.rhesus.config;
  citra = self.nixosConfigurations.citra.config;
  sources = {
    # Exclude the SBEE IPv4 addresses carried by the same interfaces.
    wireguard = map (address: lib.head (lib.splitString "/" address)) (
      lib.filter (lib.hasInfix ":") (
        rhesus.networking.wg-quick.interfaces.wireguard.address
        ++ citra.networking.wireguard.interfaces.wireguard.ips
      )
    );
    "tinc.naru" =
      lib.concatMap
        (machine: [
          machine.networking.naru.ipv4
          machine.networking.naru.ipv6
        ])
        [
          rhesus
          citra
        ];
  };
in
{
  programs.ssh.extraConfig = ''
    # Use certificate-based authentication for mesh networks
    Host *.x
      StrictHostKeyChecking accept-new
  '';

  # Cask shares public SSH with Gitea and keeps its bootstrap path until
  # out-of-band recovery is verified. Ordinary hosts need no public SSH.
  services.openssh.openFirewall = lib.mkIf (config.networking.hostName != "cask") false;
  networking.firewall.extraInputRules = lib.mkIf (config.networking.hostName != "cask") (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        interface: addresses:
        lib.concatMapStringsSep "\n" (
          address:
          let
            family = if lib.hasInfix ":" address then "ip6" else "ip";
          in
          lib.concatMapStringsSep "\n" (port: ''
            iifname "${interface}" ${family} saddr ${address} tcp dport ${toString port} accept
          '') config.services.openssh.ports
        ) addresses
      ) sources
    )
  );
}
