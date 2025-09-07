{
  inputs = {
    # keep-sorted start
    apple-silicon.inputs.nixpkgs.follows = "nixpkgs";
    apple-silicon.inputs.treefmt-nix.follows = "treefmt-nix";
    apple-silicon.url = "github:nix-community/nixos-apple-silicon";
    catppuccin.url = "github:catppuccin/nix";
    clan-core.inputs.disko.follows = "disko";
    clan-core.inputs.flake-parts.follows = "flake-parts";
    clan-core.inputs.nix-darwin.follows = "nix-darwin";
    clan-core.inputs.nixos-facter-modules.follows = "nixos-facter-modules";
    clan-core.inputs.sops-nix.follows = "sops-nix";
    clan-core.inputs.systems.follows = "systems";
    clan-core.inputs.treefmt-nix.follows = "treefmt-nix";
    clan-core.url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nur.inputs.flake-parts.follows = "flake-parts";
    nur.inputs.nixpkgs.follows = "nixpkgs";
    nur.url = "github:nix-community/NUR";
    sops-nix.url = "github:Mic92/sops-nix";
    srvos.inputs.nixpkgs.follows = "nixpkgs";
    srvos.url = "github:nix-community/srvos";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    stylix.url = "github:nix-community/stylix/release-25.05";
    systems.url = "github:nix-systems/default";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    # keep-sorted end
  };

  outputs =
    inputs@{
      flake-parts,
      systems,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import systems;
      imports = [
        ./checks/flake-module.nix
        ./formatter/flake-module.nix
        ./home-manager/flake-module.nix
        ./overlays/flake-module.nix
        ./machines/flake-module.nix
        ./modules/flake-module.nix
        ./packages/flake-module.nix
        ./shells/flake-module.nix
        ./terraform/flake-module.nix
        inputs.clan-core.flakeModules.default
        inputs.home-manager.flakeModules.home-manager
      ];
    };
}
