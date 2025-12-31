{
  self,
  pkgs,
  ...
}:
{
  imports = [
    self.inputs.srvos.nixosModules.server
    self.inputs.srvos.nixosModules.mixins-terminfo
    self.inputs.srvos.nixosModules.mixins-nix-experimental
    self.inputs.disko.nixosModules.disko
    ../../nixosModules/users.nix
    ../../nixosModules/zerotier.nix
    ../../nixosModules/dns-client.nix
    ../../nixosModules/disko-zfs.nix
    ./modules/network.nix
  ];

  clan.core.networking.targetHost = "root@10.80.169.67";

  # Disk configuration
  disko.rootDisk = "/dev/nvme0n1";

  networking.hostName = "malt";
  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfree = true;

  # UEFI boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable aarch64 emulation for building Raspberry Pi images
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  environment.systemPackages = with pkgs; [
    vim
    btop
  ];

  programs.fish.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  srvos.flake = self;
  system.stateVersion = "25.05";
}
