{
  self,
  config,
  ...
}:
let
  clanLib = self.inputs.clan-core.lib;

  wgPrefix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "taps";
    generator = "wireguard-network-wireguard";
    file = "prefix";
  };
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";
in
{
  imports = [
    ../../../nixosModules/neo4j.nix
    ../../../nixosModules/qdrant.nix
  ];

  # Enable Neo4j graph database
  services.neo4j.enable = true;

  # Enable Qdrant vector database
  services.qdrant.enable = true;

  # Environment variables for Cognee/Mem0 configuration
  # These will be used by MCP servers connecting to this machine
  environment.etc."cognee/config.env".text = ''
    # Neo4j connection
    NEO4J_URI=bolt://${maltWgIP}:7687
    NEO4J_USER=neo4j
    # Password should be set manually after first boot:
    # neo4j-admin dbms set-initial-password <password>

    # Qdrant connection
    QDRANT_HOST=${maltWgIP}
    QDRANT_HTTP_PORT=6333
    QDRANT_GRPC_PORT=6334

    # Data directories
    COGNEE_DATA_DIR=/var/lib/cognee
    MEM0_DATA_DIR=/var/lib/mem0
  '';
}
