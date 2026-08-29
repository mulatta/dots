{ config, pkgs, ... }:
let
  sshCaPubKey = ../vars/shared/openssh-ca/id_ed25519.pub/value;
in
{
  users.users.seungwon.openssh.authorizedKeys.keys = [
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAbiIX1IpgsaylNgtDb04IM4jQKlU+RVwDr8YGfXLwuHWn3xydzTYeg3o/T9UX/j2326D7tnL7kMq7XvmhuSd8Y= ssh@secretive.rhesus.local"
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
  environment.systemPackages = [ pkgs.openssh ];
}
