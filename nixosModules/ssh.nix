{
  programs.ssh.knownHosts.ssh-ca.extraHostNames = [
    "*.x" # WireGuard mesh
    "*.i" # ZeroTier internal
  ];

  programs.ssh.extraConfig = ''
    # Use certificate-based authentication for mesh networks
    Host *.x *.i
      StrictHostKeyChecking accept-new
      UserKnownHostsFile /dev/null
  '';
}
