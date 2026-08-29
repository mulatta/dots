{ pkgs, ... }:
let
  sshCaPubKey = ../vars/shared/openssh-ca/id_ed25519.pub/value;
in
{
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
