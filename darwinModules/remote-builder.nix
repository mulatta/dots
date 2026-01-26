{ config, ... }:
{
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

    Host eta
      HostName jump.sjanglab.org
      Port 10022
      IdentityFile ${config.sops.secrets.psi-builder.path}
  '';
}
