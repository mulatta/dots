{
  self,
  config,
  pkgs,
  ...
}:
{
  imports = [
    self.nixosModules.default
    self.inputs.srvos.nixosModules.server
    self.inputs.disko.nixosModules.disko
    ./modules/disko.nix
    ./modules/initrd.nix
    ./modules/nixbot.nix
    ./modules/tribuchet.nix
    ./modules/network.nix
    ./modules/neko
    ../../nixosModules/gnome-desktop.nix
  ];

  networking.hostName = "citra";
  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ self.overlays.default ];

  environment.systemPackages = with pkgs; [
    vim
    btop
  ];
  programs.fish.enable = true;

  # SMART health and temperature alerts for the two mirrored SSDs.
  services.smartd.enable = true;

  # The Nuvoton NCT6687 Super I/O has no mainline driver; without it the
  # CPU cooler fans have no RPM or PWM readout. Monitoring only: fan curves
  # stay in the BIOS.
  boot.extraModulePackages = [ config.boot.kernelPackages.nct6687d ];
  boot.kernelModules = [ "nct6687" ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  system.stateVersion = "26.05";
}
