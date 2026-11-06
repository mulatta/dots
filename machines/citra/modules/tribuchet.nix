{
  config,
  pkgs,
  self,
  ...
}:
let
  inherit (self.inputs) tribuchet;
  tribuchetPkg = tribuchet.packages.${pkgs.stdenv.hostPlatform.system}.default;
  gen = config.clan.core.vars.generators.tribuchet.files;
  hubPort = 7437;
in
{
  imports = [
    tribuchet.nixosModules.default
    self.inputs.flakelet.nixosModules.flakelet
  ];

  # psi's worker uses worker.{crt,key} from this CA.
  clan.core.vars.generators.tribuchet = {
    files = {
      "ca.crt".secret = false;
      "ca.key" = { };
      "hub.crt".secret = false;
      "hub.key" = { };
      "worker.crt".secret = false;
      "worker.key" = { };
    };
    runtimeInputs = [ tribuchetPkg ];
    # SAN must match the address psi dials.
    script = ''
      tribuchet ca init --dir "$out"
      tribuchet ca issue citra.n --dir "$out"
      tribuchet ca issue worker --dir "$out"
      mv "$out/citra.n.crt" "$out/hub.crt"
      mv "$out/citra.n.key" "$out/hub.key"
    '';
  };

  environment.etc."tribuchet/ca/ca.crt".source = gen."ca.crt".path;
  environment.etc."tribuchet/ca/hub.crt".source = gen."hub.crt".path;
  environment.etc."tribuchet/ca/hub.key".source = gen."hub.key".path;

  # Tracks main like the psi worker so both protocol ends stay in step.
  services.flakelets = {
    enable = true;
    services.tribuchet-hub = {
      flake = "github:Mic92/tribuchet";
      output = "flakelets.hub";
      autoUpdate.enable = true;
      settings = {
        port = hubPort;
        inherit (config.services.tribuchet-hub.externalBuilders) nixConfigPath;
        hub.metrics-listen = "127.0.0.1:7438";
      };
    };
  };

  services.tribuchet-hub.externalBuilders = {
    enable = true;
    # The flakelet's RuntimeDirectory.
    nixConfigPath = "/run/tribuchet-hub/nix.conf";
    dynamic = true;
  };

  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [ hubPort ];

  # Each external build holds a uid slot.
  nix.settings.id-count = config.services.tribuchet-hub.externalBuilders.maxJobsCap * 65536;
}
