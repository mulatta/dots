{ lib, pkgs, ... }:
let
  apps = [
    1444383602 # Goodnotes
    869223134 # KakaoTalk
    1475387142 # Tailscale
    1451685025 # WireGuard
    497799835 # Xcode
  ];
in
{
  environment.systemPackages = [ pkgs.mas ];

  # nix-darwin only runs its predefined activation scripts, so hook into postActivation.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "Syncing apps from the App Store..." >&2
    PATH="${lib.makeBinPath [ pkgs.mas ]}:$PATH" ${pkgs.python3.interpreter} ${./declarative-app-store.py} ${toString apps}
  '';

  # Installed apps are only reconciled, never upgraded; the App Store keeps them current.
  system.defaults.CustomSystemPreferences."/Library/Preferences/com.apple.commerce".AutoUpdate = true;
}
