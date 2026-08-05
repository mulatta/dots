{
  config,
  lib,
  self,
  ...
}:
let
  grpcSupported = !lib.hasInfix "pre" config.nix.package.version;
in
{
  # nix-grpc-store only ships a NixOS client module, but it only extends
  # nix.settings, which nix-darwin also exposes.
  imports = [ "${self.inputs.nix-grpc-store}/nixos/client.nix" ];

  programs.nix-grpc-store.enable = grpcSupported;

  nix.distributedBuilds = true;

  nix.buildMachines = lib.optionals grpcSupported [
    {
      hostName = "grpc://10.100.0.2:50051?insecure=1";
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
