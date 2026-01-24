{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  # Helper to read clan vars
  readVarFile =
    machine: generator: file:
    let
      path = self + "/vars/per-machine/${machine}/${generator}/${file}/value";
    in
    if builtins.pathExists path then lib.strings.trim (builtins.readFile path) else null;

  # DNS resolver target: taps WireGuard IP
  wgPrefix = readVarFile "taps" "wireguard-network-wireguard" "prefix";
  tapsWireguardIP = if wgPrefix != null then "${wgPrefix}::1" else null;

  # Sops-managed private key path (clan vars generator)
  secretPath = config.clan.core.vars.generators.wireguard-keys-wireguard.files.privatekey.path;

  wgQuickWrapper = pkgs.writeShellScript "wg-quick-wireguard-start" ''
    for i in $(seq 1 60); do
      if [ -f "${secretPath}" ]; then
        ${pkgs.wireguard-tools}/bin/wg-quick down wireguard 2>/dev/null || true
        ${pkgs.wireguard-tools}/bin/wg-quick up wireguard
        exec sleep 2147483647
      fi
      sleep 1
    done
    echo "Timed out waiting for wireguard private key at ${secretPath}"
    exit 1
  '';
in
{
  # DNS resolver for .x domain -> taps WireGuard IP
  environment.etc."resolver/x" = lib.mkIf (tapsWireguardIP != null) {
    text = "nameserver ${tapsWireguardIP}\n";
  };

  # Suppress nix-darwin wg-quick module auto-daemon (which races with sops secret)
  # mkForce needed because clan-core wireguard darwinModule may set this
  networking.wg-quick.interfaces.wireguard.autostart = lib.mkForce false;

  # Custom launchd daemon: waits for sops secret before starting wg-quick
  launchd.daemons.wg-quick-wireguard.serviceConfig = {
    ProgramArguments = [ "${wgQuickWrapper}" ];
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
    KeepAlive.PathState.${secretPath} = true;
    StandardOutPath = "/var/log/wg-quick-wireguard.log";
    StandardErrorPath = "/var/log/wg-quick-wireguard.log";
  };
}
