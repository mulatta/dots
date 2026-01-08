{
  lib,
  pkgs,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  rbw-pinentry = self.packages.${system}.rbw-pinentry;
in
{
  programs.rbw = {
    enable = true;
    settings = {
      email = lib.mkDefault "seungwon@mulatta.io";
      base_url = "https://vaultwarden.mulatta.io";
      # Use rbw-pinentry for permanent caching in system secure storage
      # macOS: Keychain, Linux: Secret Service (KDE Wallet, GNOME Keyring)
      pinentry = rbw-pinentry;
    };
  };

  # Install rbw-pinentry for permanent password caching
  home.packages = [ rbw-pinentry ];
}
