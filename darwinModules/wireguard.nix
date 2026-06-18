{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  readVarFile = self.lib.readVarFile;

  # DNS resolver target: taps WireGuard IP
  wgPrefix = readVarFile "taps" "wireguard-network-wireguard" "prefix";
  tapsWireguardIP = if wgPrefix != null then "${wgPrefix}::1" else null;

  # Sops-managed private key path (clan vars generator)
  secretPath = config.clan.core.vars.generators.wireguard-keys-wireguard.files.privatekey.path;

  sbeeAdminAddress = "10.100.0.200/32";
  sbeeAdminPeers = [
    {
      # eta wg-admin
      publicKey = "3fJoR3zVE9zpfKEXqvavLksOlWeFxqZd3f2fFUOkW1Y=";
      endpoint = "141.164.53.203:51820";
      allowedIPs = [ "10.100.0.1/32" ];
      persistentKeepalive = 25;
    }
  ];

  wgQuickWrapper = pkgs.writeShellScript "wg-quick-wireguard-start" ''
    /bin/wait4path "${secretPath}"
    ${pkgs.wireguard-tools}/bin/wg-quick down wireguard 2>/dev/null || true
    # Kill stale processes from previous runs that AbandonProcessGroup kept alive.
    # Without this, old route-monitor manages routes for a dead utun interface
    # while the new wg-quick creates a fresh utun without routes.
    pkill -f 'wireguard-go utun' 2>/dev/null || true
    pkill -f 'route -n monitor' 2>/dev/null || true
    rm -rf /var/run/wireguard 2>/dev/null || true
    ${pkgs.wireguard-tools}/bin/wg-quick up wireguard
  '';
in
{
  # DNS resolver for .x domain -> taps WireGuard IP
  environment.etc."resolver/x" = lib.mkIf (tapsWireguardIP != null) {
    text = "nameserver ${tapsWireguardIP}\n";
  };

  # Extend the existing clan host WireGuard identity with the SBEE admin
  # network. infra registers rhesus' clan public key, so no second Darwin
  # WireGuard identity is needed.
  networking.wg-quick.interfaces.wireguard.address = lib.mkAfter [ sbeeAdminAddress ];
  networking.wg-quick.interfaces.wireguard.peers = lib.mkAfter sbeeAdminPeers;

  # Suppress nix-darwin wg-quick module auto-daemon (which races with sops secret)
  # mkForce needed because clan-core wireguard darwinModule may set this
  networking.wg-quick.interfaces.wireguard.autostart = lib.mkForce false;

  # Custom launchd daemon: wait4path blocks until sops secret exists, then starts wg-quick
  launchd.daemons.wg-quick-wireguard.serviceConfig = {
    ProgramArguments = [
      "/bin/sh"
      "-c"
      "/bin/wait4path /nix/store && exec ${wgQuickWrapper}"
    ];
    EnvironmentVariables.PATH = lib.concatStringsSep ":" [
      "${pkgs.wireguard-tools}/bin"
      "${pkgs.wireguard-go}/bin"
      "${pkgs.coreutils}/bin"
      "${pkgs.gnugrep}/bin"
      "${pkgs.iproute2mac}/bin"
      "/usr/bin"
      "/usr/sbin"
      "/bin"
      "/sbin"
    ];
    RunAtLoad = true;
    # wg-quick forks wireguard-go as a daemon; let it survive after wrapper exits
    AbandonProcessGroup = true;
    StandardOutPath = "/var/log/wg-quick-wireguard.log";
    StandardErrorPath = "/var/log/wg-quick-wireguard.log";
  };
}
