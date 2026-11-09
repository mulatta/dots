{
  config,
  pkgs,
  lib,
  self,
  ...
}:
let
  sshCaPubKey = ../vars/shared/openssh-ca/id_ed25519.pub/value;
  citra = self.nixosConfigurations.citra.config;
  allowedSources = [
    "127.0.0.1"
    "::1"
    citra.networking.naru.ipv4
    citra.networking.naru.ipv6
  ]
  ++ map (address: lib.head (lib.splitString "/" address)) (
    lib.filter (lib.hasInfix ":") citra.networking.wireguard.interfaces.wireguard.ips
  );
in
{
  users.users.seungwon.openssh.authorizedKeys.keys = [
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAbiIX1IpgsaylNgtDb04IM4jQKlU+RVwDr8YGfXLwuHWn3xydzTYeg3o/T9UX/j2326D7tnL7kMq7XvmhuSd8Y= ssh@secretive.rhesus.local"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILsNxLymPlu3+FJmn1/uBATTN8xgJ2UJQi7VddQJfif6 seungwon@citra"
  ];
  users.users.root.openssh.authorizedKeys.keys =
    config.users.users.seungwon.openssh.authorizedKeys.keys;

  programs.ssh.knownHosts.ssh-ca = {
    certAuthority = true;
    hostNames = [
      "*.i" # Internet bootstrap
      "*.x" # WireGuard mesh
      "*.n" # Tinc mesh
      "*.local" # mDNS/Bonjour
      "*.sjanglab.org"
    ];
    publicKeyFile = sshCaPubKey;
  };

  environment.etc."ssh/ssh_config.d/mesh.conf".text = ''
    # WireGuard mesh
    Host *.x
      StrictHostKeyChecking accept-new

    # SBEE Tinc mesh
    Host eta.n psi.n rho.n tau.n
      Port 10022

    # Local network
    Host *.local
      StrictHostKeyChecking accept-new
  '';
  # Darwin's SSH socket remains reachable, but only citra may authenticate
  # remotely. Keep loopback usable for local maintenance.
  services.openssh.extraConfig = ''
    AllowUsers ${lib.concatMapStringsSep " " (address: "*@${address}") allowedSources}
  '';

  environment.systemPackages = [ pkgs.openssh ];
}
