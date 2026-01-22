{
  inputs = {
    # keep-sorted start
    clan-core.inputs.disko.follows = "disko";
    clan-core.inputs.flake-parts.follows = "flake-parts";
    clan-core.inputs.nix-darwin.follows = "nix-darwin";
    clan-core.inputs.sops-nix.follows = "sops-nix";
    clan-core.inputs.systems.follows = "systems";
    clan-core.inputs.treefmt-nix.follows = "treefmt-nix";
    clan-core.url = "https://git.clan.lol/clan/clan-core/archive/25.11.tar.gz";
    cognee-nix.inputs.flake-parts.follows = "flake-parts";
    cognee-nix.inputs.nixpkgs.follows = "nixpkgs";
    cognee-nix.inputs.systems.follows = "systems";
    cognee-nix.inputs.treefmt-nix.follows = "treefmt-nix";
    cognee-nix.url = "github:mulatta/cognee-nix";
    direnv-instant.inputs.nixpkgs.follows = "nixpkgs";
    direnv-instant.url = "github:Mic92/direnv-instant";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    jmt.inputs.nixpkgs.follows = "nixpkgs";
    jmt.url = "github:mulatta/jmt";
    llm-agents.url = "github:numtide/llm-agents.nix";
    niks3.inputs.nixpkgs.follows = "nixpkgs";
    niks3.url = "github:Mic92/niks3";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nixpkgs.url = "git+https://github.com/mulatta/nixpkgs?shallow=1&ref=main";
    sops-nix.url = "github:Mic92/sops-nix";
    srvos.inputs.nixpkgs.follows = "nixpkgs";
    srvos.url = "github:nix-community/srvos";
    systems.url = "github:nix-systems/default";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    zjstatus.url = "github:dj95/zjstatus";
    zsh-helix-mode.url = "github:Multirious/zsh-helix-mode";
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
        ./home-manager/modules/helix/flake-module.nix
        ./home-manager/modules/yazi/flake-module.nix
        ./overlays/flake-module.nix
        ./machines/flake-module.nix
        ./packages/flake-module.nix
        ./shells/flake-module.nix
        ./terraform/flake-module.nix
        inputs.clan-core.flakeModules.default
        inputs.home-manager.flakeModules.home-manager
      ];

      flake.nixosModules.imports = [ ./nixosModules ];
      flake.darwinModules.imports = [ ./darwinModules ];
    };
}
