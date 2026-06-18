{
  self,
  config,
  lib,
  ...
}:
let
  cfg = config.services.qdrant;

  wgPrefix = self.lib.wgPrefix;
  localSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  localWgIP = "${wgPrefix}:${localSuffix}";
in
{
  config = lib.mkIf cfg.enable {
    users.users.qdrant = {
      isSystemUser = true;
      group = "qdrant";
      home = "/var/lib/qdrant";
    };
    users.groups.qdrant = { };

    systemd.services.qdrant.serviceConfig.DynamicUser = lib.mkForce false;
    systemd.services.qdrant.serviceConfig.User = "qdrant";
    systemd.services.qdrant.serviceConfig.Group = "qdrant";

    disko.devices.zpool.zroot.datasets."qdrant" = {
      type = "zfs_fs";
      mountpoint = "/var/lib/qdrant";
      options = {
        compression = "lz4";
        recordsize = "128K"; # Good for sequential vector reads
        "com.sun:auto-snapshot" = "true";
      };
    };

    services.qdrant = {
      settings = {
        # Network: bind to WireGuard IP only
        service = {
          host = localWgIP;
          http_port = 6333;
          grpc_port = 6334;
          # Performance settings
          max_workers = 2; # Conservative for N100
          enable_cors = true;
        };

        storage = {
          storage_path = "/var/lib/qdrant/storage";
          snapshots_path = "/var/lib/qdrant/snapshots";
          # Performance: keep HNSW index on disk for memory efficiency
          on_disk_payload = true;
        };

        # HNSW index settings (memory efficient)
        hnsw_index = {
          on_disk = true;
        };

        # Disable telemetry
        telemetry_disabled = true;

        log_level = "INFO";
      };
    };

    # Resource limits for N100 + 32GB
    systemd.services.qdrant.serviceConfig = {
      MemoryMax = "6G";
      CPUQuota = "200%"; # 2 cores
    };

    # ZFS auto-creates the dataset root-owned; reset it to the service user.
    systemd.tmpfiles.rules = [
      "Z /var/lib/qdrant 0750 qdrant qdrant -"
    ];

    networking.firewall.interfaces."wireguard".allowedTCPPorts = [
      6333 # HTTP API
      6334 # gRPC API
    ];
  };
}
