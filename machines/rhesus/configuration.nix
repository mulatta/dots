{
  self,
  pkgs,
  ...
}:
{
  imports = [
    self.inputs.sops-nix.darwinModules.sops
    self.inputs.srvos.darwinModules.common
    self.inputs.srvos.darwinModules.mixins-nix-experimental
    self.inputs.srvos.darwinModules.mixins-terminfo
    ../../darwinModules/app-store
    ../../darwinModules/desktop.nix
    ../../darwinModules/homebrew.nix
    ../../darwinModules/karabiner.nix
    ../../darwinModules/nix-daemon.nix
    ../../darwinModules/nix-index.nix
    ../../darwinModules/openssh.nix
    ../../darwinModules/remote-builder.nix
    ../../darwinModules/sudo.nix
    ../../darwinModules/wireguard.nix
    ../../darwinModules/zerotier.nix
  ];

  clan.core.networking.targetHost = "root@rhesus.x";
  system.primaryUser = "seungwon";

  networking.hostName = "rhesus";
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  clan.core.networking.zerotier = {
    enable = true;
    controller.machineName = "taps";
  };

  system.activationScripts.postActivation.text = ''
    # disable fseventsd on /nix volume
    mkdir -p /nix/.fseventsd
    test -e /nix/.fseventsd/no_log || touch /nix/.fseventsd/no_log
  '';

  # Use user's existing age key for sops-nix
  sops.age.keyFile = "/Users/seungwon/.config/sops/age/keys.txt";
  sops.age.sshKeyPaths = [ ];
  sops.gnupg.sshKeyPaths = [ ];

  users.users.seungwon.home = "/Users/seungwon";

  environment.systemPackages = with pkgs; [
    curl
    nixos-rebuild
    python3
    systemctl-macos
    tree
    wget
  ];

  system.stateVersion = 6;

  srvos.flake = self;
}
