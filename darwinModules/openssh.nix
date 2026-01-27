let
  sshCaPubKey = ../vars/per-machine/taps/openssh/ssh.id_ed25519.pub/value;
in
{
  programs.ssh.knownHosts.ssh-ca = {
    certAuthority = true;
    hostNames = [
      "*.x" # WireGuard mesh
      "*.i" # ZeroTier internal
      "*.local" # mDNS/Bonjour
    ];
    publicKeyFile = sshCaPubKey;
  };

  environment.etc."ssh/ssh_config.d/mesh.conf".text = ''
    # WireGuard mesh
    Host *.x
      StrictHostKeyChecking accept-new

    # ZeroTier internal
    Host *.i
      StrictHostKeyChecking accept-new

    # Local network
    Host *.local
      StrictHostKeyChecking accept-new
  '';
}
