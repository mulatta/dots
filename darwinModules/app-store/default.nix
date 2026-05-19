{ pkgs, ... }:
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

  system.activationScripts.appStore.text = ''
    echo "Syncing apps from the App Store..."
    ${pkgs.python3.interpreter} ${./declarative-app-store.py} ${builtins.toString apps}
  '';
}
