{
  self,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    self.inputs.srvos.darwinModules.common
    self.inputs.sops-nix.darwinModules.sops
    self.inputs.srvos.darwinModules.mixins-terminfo
    self.inputs.srvos.darwinModules.mixins-nix-experimental
    ../../darwinModules/clan-zerotier.nix
    ../../darwinModules/desktop.nix
    ../../darwinModules/dns-client.nix
    ../../darwinModules/docker.nix
    ../../darwinModules/homebrew.nix
    ../../darwinModules/linux-builder.nix
    ../../darwinModules/nix-daemon.nix
    ../../darwinModules/nix-index.nix
    ../../darwinModules/sudo.nix
    ../../darwinModules/zerotier.nix
  ];

  clan.core.networking.targetHost = lib.mkForce "root@rhesus.x";
  system.primaryUser = "seungwon";

  networking.hostName = "rhesus";
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  clan.core.networking.zerotier = {
    enable = true;
    controller.machineName = "taps";
  };

  system.activationScripts.postActivation.text = ''
    # disable spotlight
    # launchctl unload -w /System/Library/LaunchDaemons/com.apple.metadata.mds.plist >/dev/null 2>&1 || true
    # disable fseventsd on /nix volume
    mkdir -p /nix/.fseventsd
    test -e /nix/.fseventsd/no_log || touch /nix/.fseventsd/no_log
  '';

  # Use user's existing age key for sops-nix
  sops.age.keyFile = "/Users/seungwon/.config/sops/age/keys.txt";
  sops.age.sshKeyPaths = [ ];
  sops.gnupg.sshKeyPaths = [ ];

  users.users.seungwon.home = "/Users/seungwon";

  environment.systemPackages = [
    self.packages.${pkgs.stdenv.hostPlatform.system}.systemctl-macos
    pkgs.nixos-rebuild
    pkgs.python3
    pkgs.uv
    pkgs.tree
    pkgs.curl
    pkgs.wget
    pkgs.nodejs_24
    pkgs.parallel
  ];

  system.stateVersion = 6;

  srvos.flake = self;
}
