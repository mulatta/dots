{
  programs.ssh.extraConfig = ''
    # Use certificate-based authentication for mesh networks
    Host *.x
      StrictHostKeyChecking accept-new
  '';
}
