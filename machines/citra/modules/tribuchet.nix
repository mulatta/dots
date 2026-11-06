{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  inherit (self.inputs) tribuchet;
  tribuchetPkg = tribuchet.packages.${pkgs.stdenv.hostPlatform.system}.default;
  gen = config.clan.core.vars.generators.tribuchet.files;
  hub = config.services.tribuchet-hub;

  # Naru runs with StrictSubnets, so a source address proves the peer.
  psiNaru = file: lib.trim (builtins.readFile "${self.inputs.dure}/sbee/hosts/psi/naru/${file}");
in
{
  imports = [ tribuchet.nixosModules.default ];

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

  services.tribuchet-hub = {
    enable = true;
    settings.hub.metrics-listen = "127.0.0.1:7438";
    externalBuilders = {
      enable = true;
      dynamic = true;
    };
  };

  networking.firewall.extraInputRules = ''
    iifname "tinc.naru" ip saddr ${psiNaru "ip4"} tcp dport ${toString hub.port} accept
    iifname "tinc.naru" ip6 saddr ${psiNaru "ip6"} tcp dport ${toString hub.port} accept
  '';

  # Each external build holds a uid slot.
  nix.settings.id-count = hub.externalBuilders.maxJobsCap * 65536;
}
