{
  programs.ssh.extraConfig = ''
    # Use certificate-based authentication for mesh networks
    Host *.x *.z
      StrictHostKeyChecking accept-new
  '';
}
