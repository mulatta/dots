{ config, ... }:
{
  # Trust host keys for nix-daemon (root) SSH connections
  programs.ssh.knownHosts."jump.sjanglab.org" = {
    hostNames = [ "[jump.sjanglab.org]:10022" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjsbwEMkTr9AuVTHdu5LL84huMVbdTvOruDCzQ5atCW";
  };
  programs.ssh.knownHosts."psi" = {
    hostNames = [ "[10.100.0.2]:10022" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINJaASSEAjKBBh4/t6MrSKbuoYiLPUq7lq1CONTp7Ntp";
  };

  sops.secrets.psi-builder = {
    sopsFile = ../sops/builders/psi-builder/secret;
    format = "binary";
  };

  nix.distributedBuilds = true;

  nix.buildMachines = [
    {
      hostName = "psi";
      sshUser = "root";
      protocol = "ssh-ng";
      sshKey = config.sops.secrets.psi-builder.path;
      systems = [ "x86_64-linux" ];
      maxJobs = 24;
      supportedFeatures = [
        "big-parallel"
        "kvm"
        "nixos-test"
      ];
    }
  ];

  # let system level nix-daemon could access the configuration
  environment.etc."ssh/ssh_config.d/remote-builder.conf".text = ''
    Host psi
      HostName 10.100.0.2
      Port 10022
      ProxyJump eta
      IdentityAgent none

    Host eta
      HostName jump.sjanglab.org
      Port 10022
      IdentityFile ${config.sops.secrets.psi-builder.path}
      IdentityAgent none
      ControlMaster auto
      ControlPath /tmp/ssh-nix-builder-%r@%h:%p
      ControlPersist 10m
  '';
}
