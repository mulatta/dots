{
  programs.ssh.extraConfig = ''
    # Use certificate-based authentication for mesh networks
    Host *.x *.i *.z
      StrictHostKeyChecking accept-new
  '';
}
