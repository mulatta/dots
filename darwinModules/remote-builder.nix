{
  config,
  lib,
  self,
  ...
}:
let
  grpcSupported = !lib.hasInfix "pre" config.nix.package.version;
  certs = config.sops.secrets;
  # Keep daemon credentials out of the URI. nix-grpc-store discovers the
  # root-only client pair in /run/nix-grpc-store when nix-daemon opens the store.
  grpcUri = "grpc://psi.sjanglab.org:50051?ca-cert=${certs.nix-grpc-ca-cert.path}";
in
{
  # Client module only extends options shared by NixOS and nix-darwin.
  imports = [ self.inputs.nix-grpc-store.nixosModules.client ];

  programs.nix-grpc-store.enable = grpcSupported;

  sops.secrets = {
    nix-grpc-ca-cert = {
      path = "/run/nix-grpc-store/ca.crt";
      mode = "0444";
    };
    nix-grpc-client-cert = {
      path = "/run/nix-grpc-store/client.crt";
      mode = "0444";
    };
    nix-grpc-client-key = {
      path = "/run/nix-grpc-store/client.key";
      mode = "0400";
    };
  };

  nix.distributedBuilds = true;

  nix.buildMachines = lib.optionals grpcSupported [
    {
      hostName = grpcUri;
      protocol = null;
      systems = [ "x86_64-linux" ];
      maxJobs = 24;
      supportedFeatures = [
        "big-parallel"
        "kvm"
        "nixos-test"
      ];
    }
  ];
}
