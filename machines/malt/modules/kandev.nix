{
  lib,
  pkgs,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  kandev = self.inputs.llm-agents.packages.${system}.kandev.override {
    claudeSupport = true;
    codexSupport = true;
    piSupport = true;
    extraPackages = [ pkgs.gh ];
  };
  stateDir = "/var/lib/kandev";
  port = 38429;

  wgPrefix = self.lib.wgPrefix;
  tapsWgIP = "${wgPrefix}::1";
in
{
  disko.devices.zpool.zroot.datasets.kandev = {
    type = "zfs_fs";
    mountpoint = stateDir;
    options."com.sun:auto-snapshot" = "true";
  };

  users.users.kandev = {
    isSystemUser = true;
    group = "kandev";
    home = stateDir;
  };
  users.groups.kandev = { };

  # Local agents may need the Nix daemon, but stay isolated from every human
  # home directory and from services outside Kandev's own state directory.
  nix.settings.extra-allowed-users = [ "kandev" ];

  systemd.services.kandev = {
    description = "Kandev agentic development platform";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      HOME = stateDir;
      KANDEV_HOME_DIR = stateDir;
      # The launcher probes localhost even when the externally advertised
      # address is WireGuard-only. Bind dual-stack and enforce reachability in
      # nftables so launcher health and taps' IPv6 upstream both work.
      KANDEV_SERVER_HOST = "::";
      KANDEV_SERVER_PORT = toString port;
      KANDEV_DATABASE_DRIVER = "sqlite";
      # Enabling the local Docker executor would require root-equivalent
      # daemon access. SSH executors remain available without it.
      KANDEV_DOCKER_ENABLED = "false";
    };

    unitConfig.RequiresMountsFor = [ stateDir ];

    serviceConfig = {
      User = "kandev";
      Group = "kandev";
      WorkingDirectory = stateDir;
      StateDirectory = "kandev";
      StateDirectoryMode = "0750";
      ExecStart = "${lib.getExe kandev} --headless";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";

      CapabilityBoundingSet = "";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ stateDir ];
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      RestrictSUIDSGID = true;
    };
  };

  # oauth2-proxy on taps is the authentication boundary. Do not let another
  # WireGuard peer bypass it by connecting to Kandev directly.
  networking.firewall.extraInputRules = lib.mkAfter ''
    iifname "wireguard" ip6 saddr ${tapsWgIP} tcp dport ${toString port} accept comment "Allow Kandev only from taps proxy"
  '';
}
