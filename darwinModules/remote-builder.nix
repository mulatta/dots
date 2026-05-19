{ config, ... }:
let
  sshKeyPath = config.clan.core.vars.generators.psi-builder.files.ssh-key.path;
in
{
  # Trust host keys for nix-daemon (root) SSH connections
  programs.ssh.knownHosts."jump.sjanglab.org" = {
    hostNames = [
      "[jump.sjanglab.org]:10022"
      "[10.100.0.1]:10022"
    ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjsbwEMkTr9AuVTHdu5LL84huMVbdTvOruDCzQ5atCW";
  };
  programs.ssh.knownHosts."psi" = {
    hostNames = [ "[10.100.0.2]:10022" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINJaASSEAjKBBh4/t6MrSKbuoYiLPUq7lq1CONTp7Ntp";
  };

  clan.core.vars.generators.psi-builder = {
    files.ssh-key = {
      secret = true;
      deploy = true;
      mode = "0600";
      owner = "root";
      group = "wheel";
    };
    prompts.ssh-key = {
      description = "SSH private key (OpenSSH PEM, BEGIN..END) for psi remote builder via eta jump host. Paste the full key including header/footer, then Ctrl-D to finish.";
      type = "multiline-hidden";
    };
    script = ''
      cp "$prompts/ssh-key" "$out/ssh-key"
    '';
  };

  nix.distributedBuilds = true;

  nix.buildMachines = [
    {
      hostName = "psi";
      sshUser = "root";
      protocol = "ssh-ng";
      sshKey = sshKeyPath;
      systems = [ "x86_64-linux" ];
      maxJobs = 24;
      supportedFeatures = [
        "big-parallel"
        "kvm"
        "nixos-test"
      ];
    }
  ];

  # nix-daemon (running as root) reaches psi via eta over wg-admin with a
  # clan-vars deployed key. Scope to `localuser root` so the system-wide ssh_config
  # does not poison interactive `ssh root@eta` from a normal user shell:
  # without this, the unreadable IdentityFile and `IdentityAgent none`
  # were appended to every user's ssh and blocked auth via Secretive.
  environment.etc."ssh/ssh_config.d/remote-builder.conf".text = ''
    Match localuser root host psi
      HostName 10.100.0.2
      Port 10022
      ProxyJump eta
      IdentityAgent none

    Match localuser root host eta
      HostName 10.100.0.1
      Port 10022
      IdentityFile ${sshKeyPath}
      IdentityAgent none
      ControlMaster auto
      ControlPath /tmp/ssh-nix-builder-%r@%h:%p
      ControlPersist 10m
  '';
}
