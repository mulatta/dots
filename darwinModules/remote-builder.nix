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
  grpcUri = "grpc://psi:50051?ca-cert=${certs.nix-grpc-ca-cert.path}";
in
{
  # nix-grpc-store only ships a NixOS client module, but it only extends
  # nix.settings, which nix-darwin also exposes.
  imports = [ "${self.inputs.nix-grpc-store}/nixos/client.nix" ];

  programs.nix-grpc-store.enable = grpcSupported;

  sops.secrets = {
    nix-grpc-ca-cert = {
      sopsFile = ../sops/rhesus.yaml;
      path = "/run/nix-grpc-store/ca.crt";
      mode = "0444";
    };
    nix-grpc-client-cert = {
      sopsFile = ../sops/rhesus.yaml;
      path = "/run/nix-grpc-store/client.crt";
      mode = "0444";
    };
    nix-grpc-client-key = {
      sopsFile = ../sops/rhesus.yaml;
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
