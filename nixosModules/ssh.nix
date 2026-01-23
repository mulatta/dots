{
  programs.ssh.knownHosts.ssh-ca = {
    publicKeyFile = ../vars/shared/openssh-ca/id_ed25519.pub/value;
    extraHostNames = [
      "*.x" # WireGuard mesh
      "*.i" # ZeroTier internal
    ];
  };

  programs.ssh.extraConfig = ''
    # Use certificate-based authentication for mesh networks
    Host *.x *.i
      StrictHostKeyChecking accept-new
      UserKnownHostsFile /dev/null
  '';
}
