{
  self,
  config,
  lib,
  ...
}:
let
  cfg = config.services.neo4j;

  clanLib = self.inputs.clan-core.lib;

  wgPrefix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "taps";
    generator = "wireguard-network-wireguard";
    file = "prefix";
  };
  localSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  localWgIP = "${wgPrefix}:${localSuffix}";
in
{
  config = lib.mkIf cfg.enable {
    # ZFS dataset for Neo4j data
    disko.devices.zpool.zroot.datasets."neo4j" = {
      type = "zfs_fs";
      mountpoint = "/var/lib/neo4j";
      options = {
        compression = "lz4";
        recordsize = "16K"; # Optimized for graph DB random access
        "com.sun:auto-snapshot" = "true";
      };
    };

    services.neo4j = {
      # Directories
      directories = {
        home = "/var/lib/neo4j";
        data = "/var/lib/neo4j/data";
      };

      # Memory settings for N100 + 32GB
      extraServerConfig = ''
        # Memory configuration
        # - heap: query processing, GC headroom
        # - pagecache: graph data cache (larger = less disk I/O)
        dbms.memory.heap.initial_size=2g
        dbms.memory.heap.max_size=6g
        dbms.memory.pagecache.size=8g

        # Disable telemetry
        dbms.usage_report.enabled=false

        # Transaction timeout
        dbms.transaction.timeout=60s

        # Query logging for debugging
        db.logs.query.enabled=INFO
        db.logs.query.threshold=1s
      '';

      # Network: bind to WireGuard IP only
      defaultListenAddress = localWgIP;

      # Bolt protocol (for drivers)
      bolt = {
        enable = true;
        listenAddress = "${localWgIP}:7687";
        tlsLevel = "DISABLED"; # Internal network, TLS not needed
      };

      # HTTP API
      http = {
        enable = true;
        listenAddress = "${localWgIP}:7474";
      };

      # Disable HTTPS (internal network)
      https.enable = false;
    };

    # Ensure correct ownership for ZFS dataset
    systemd.tmpfiles.rules = [
      "Z /var/lib/neo4j 0750 neo4j neo4j -"
    ];

    # Firewall: allow access from WireGuard network
    networking.firewall.interfaces."wireguard".allowedTCPPorts = [
      7474 # HTTP
      7687 # Bolt
    ];
  };
}
